#!/usr/bin/env python3
"""
MB-OS Memory Daemon v2.0
========================
Leichtgewichtiger Wissens-Daemon für MB-OS.

Speicher:
  - Markdown-Dateien  → Memory.md, User.md, Skills/*.md
  - SQLite            → sessions.db (Session-Historie + Memories)

Keine externen Dependencies außer FastAPI + uvicorn (stdlib only).
KEIN PostgreSQL, KEIN Neo4j, KEIN psycopg2, KEIN requests.
"""

import os
import re
import json
import sqlite3
import logging
import hashlib
import datetime
import pathlib
from contextlib import contextmanager
from typing import Optional

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
MEMORY_DIR = pathlib.Path(
    os.getenv("MEMORY_DIR", os.path.expanduser("~/.mb-os/memory"))
)
MEMORY_MD = MEMORY_DIR / "Memory.md"
USER_MD = MEMORY_DIR / "User.md"
SKILLS_DIR = MEMORY_DIR / "Skills"
DB_PATH = MEMORY_DIR / "sessions.db"

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s — %(message)s",
)
logger = logging.getLogger("mb-memory-daemon")

# ---------------------------------------------------------------------------
# FastAPI App
# ---------------------------------------------------------------------------
app = FastAPI(
    title="MB-OS Memory Daemon",
    version="2.0",
    description="Markdown + SQLite Wissens-Daemon für MB-OS",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

# ---------------------------------------------------------------------------
# Pydantic Models
# ---------------------------------------------------------------------------

class MemoryInput(BaseModel):
    content: str
    category: Optional[str] = None   # optional: tag / category
    source: Optional[str] = None     # optional: where it came from


class MemoryQuery(BaseModel):
    query: str
    limit: int = 5


class SessionInput(BaseModel):
    session_id: Optional[str] = None
    summary: str
    topics: Optional[list[str]] = None


class SkillInput(BaseModel):
    name: str
    trigger: str
    content: str
    confidence: str = "medium"       # high / medium / low

# ---------------------------------------------------------------------------
# SQLite Helpers
# ---------------------------------------------------------------------------

def _ensure_dirs():
    """Stelle sicher, dass alle Verzeichnisse und Seed-Dateien existieren."""
    MEMORY_DIR.mkdir(parents=True, exist_ok=True)
    SKILLS_DIR.mkdir(parents=True, exist_ok=True)

    if not MEMORY_MD.exists():
        MEMORY_MD.write_text(
            "# Workspace Memory\n\n"
            "> Verwaltet vom MB-OS Memory Daemon.\n\n"
            "## Wissen\n\n"
            "_Noch keine Einträge._\n",
            encoding="utf-8",
        )
        logger.info("Memory.md angelegt.")

    if not USER_MD.exists():
        USER_MD.write_text(
            "# Nutzerprofil\n\n"
            "- **Sprache**: Deutsch\n"
            "- **OS**: MB-OS\n",
            encoding="utf-8",
        )
        logger.info("User.md angelegt.")


@contextmanager
def get_db():
    """Context-Manager für SQLite-Verbindung mit WAL-Modus."""
    conn = sqlite3.connect(str(DB_PATH), timeout=10)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA journal_mode=WAL;")
    conn.execute("PRAGMA foreign_keys=ON;")
    try:
        yield conn
        conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()


def _init_db():
    """Erstelle die SQLite-Tabellen falls nötig."""
    with get_db() as conn:
        conn.executescript("""
            CREATE TABLE IF NOT EXISTS memories (
                id          INTEGER PRIMARY KEY AUTOINCREMENT,
                content     TEXT    NOT NULL,
                category    TEXT    DEFAULT '',
                source      TEXT    DEFAULT '',
                created_at  TEXT    DEFAULT (datetime('now')),
                updated_at  TEXT    DEFAULT (datetime('now'))
            );

            CREATE TABLE IF NOT EXISTS sessions (
                id          INTEGER PRIMARY KEY AUTOINCREMENT,
                session_id  TEXT    UNIQUE NOT NULL,
                summary     TEXT    NOT NULL,
                topics      TEXT    DEFAULT '[]',
                started_at  TEXT    DEFAULT (datetime('now')),
                ended_at    TEXT
            );

            CREATE TABLE IF NOT EXISTS entities (
                id          INTEGER PRIMARY KEY AUTOINCREMENT,
                name        TEXT    UNIQUE NOT NULL,
                entity_type TEXT    DEFAULT 'concept',
                created_at  TEXT    DEFAULT (datetime('now'))
            );

            CREATE TABLE IF NOT EXISTS relations (
                id          INTEGER PRIMARY KEY AUTOINCREMENT,
                source      TEXT    NOT NULL,
                target      TEXT    NOT NULL,
                rel_type    TEXT    NOT NULL DEFAULT 'MENTIONS',
                created_at  TEXT    DEFAULT (datetime('now')),
                UNIQUE(source, target, rel_type)
            );

            CREATE VIRTUAL TABLE IF NOT EXISTS memories_fts
                USING fts5(content, category, source, content='memories', content_rowid='id');
        """)
        # Re-populate FTS index (idempotent rebuild)
        try:
            conn.execute(
                "INSERT INTO memories_fts(memories_fts) VALUES('rebuild');"
            )
        except sqlite3.OperationalError:
            pass  # table might already be synced

    logger.info("SQLite-Datenbank initialisiert: %s", DB_PATH)


def _sync_fts_insert(conn: sqlite3.Connection, rowid: int, content: str,
                     category: str, source: str):
    """Sync einen neuen Eintrag in den FTS-Index."""
    conn.execute(
        "INSERT INTO memories_fts(rowid, content, category, source) VALUES (?, ?, ?, ?);",
        (rowid, content, category, source),
    )


# ---------------------------------------------------------------------------
# Markdown Helpers
# ---------------------------------------------------------------------------

def _append_to_md(filepath: pathlib.Path, entry: str):
    """Hänge einen Eintrag an eine Markdown-Datei an."""
    now = datetime.datetime.now().strftime("%Y-%m-%d %H:%M")
    line = f"\n- **[{now}]** {entry}\n"
    with open(filepath, "a", encoding="utf-8") as f:
        f.write(line)


def _read_md(filepath: pathlib.Path) -> str:
    """Lese den gesamten Inhalt einer Markdown-Datei."""
    if filepath.exists():
        return filepath.read_text(encoding="utf-8")
    return ""


def _search_md_files(query: str, limit: int = 5) -> list[dict]:
    """Durchsuche alle MD-Dateien nach einem Suchbegriff (case-insensitive)."""
    results = []
    query_lower = query.lower()
    query_words = query_lower.split()

    md_files = list(MEMORY_DIR.glob("**/*.md"))

    for md_file in md_files:
        try:
            text = md_file.read_text(encoding="utf-8")
        except Exception:
            continue

        for i, line in enumerate(text.splitlines(), 1):
            line_lower = line.lower()
            # Prüfe ob mindestens ein Suchwort in der Zeile vorkommt
            if any(w in line_lower for w in query_words):
                # Berechne Relevanz-Score (mehr matchende Wörter = höher)
                score = sum(1 for w in query_words if w in line_lower)
                results.append({
                    "content": line.strip(),
                    "file": str(md_file.relative_to(MEMORY_DIR)),
                    "line": i,
                    "score": score,
                })

    # Sortiere nach Score (absteigend), dann nach Zeile
    results.sort(key=lambda r: (-r["score"], r["line"]))
    return results[:limit]


# ---------------------------------------------------------------------------
# Entity / Relation Extraction (offline, rule-based)
# ---------------------------------------------------------------------------

_LEARN_PATTERNS = re.compile(
    r"\b(lerne|lernt|learn(?:s|ed|ing)?|studier(?:e|t|en))\b", re.I
)
_LIKE_PATTERNS = re.compile(
    r"\b(mag|möchte|like(?:s|d)?|prefer(?:s)?|bevorzug(?:e|t))\b", re.I
)
_IS_A_PATTERNS = re.compile(
    r"\b(ist\s+ein(?:e)?|is\s+a(?:n)?)\b", re.I
)
_USE_PATTERNS = re.compile(
    r"\b(nutze?|nutzt|verwende(?:t)?|use(?:s|d)?|benutze?|benutzt)\b", re.I
)


def extract_entities_and_relations(text: str) -> tuple[list[str], list[dict]]:
    """Extrahiere Entitäten und Beziehungen aus einem Text (regelbasiert)."""
    entities: set[str] = {"User"}
    relations: list[dict] = []

    # Extrahiere Großgeschriebene Wörter als Kandidaten (> 2 Zeichen)
    candidates = [
        w.strip("!.,?;:()\"'")
        for w in text.split()
        if len(w) > 2 and w[0].isupper() and w not in ("Der", "Die", "Das",
            "Ein", "Eine", "Ich", "The", "And", "But", "User")
    ]

    if _LEARN_PATTERNS.search(text):
        for c in candidates:
            entities.add(c)
            relations.append({"source": "User", "target": c, "type": "LEARNS"})
    elif _LIKE_PATTERNS.search(text):
        for c in candidates:
            entities.add(c)
            relations.append({"source": "User", "target": c, "type": "LIKES"})
    elif _USE_PATTERNS.search(text):
        for c in candidates:
            entities.add(c)
            relations.append({"source": "User", "target": c, "type": "USES"})
    elif _IS_A_PATTERNS.search(text):
        parts = _IS_A_PATTERNS.split(text, maxsplit=1)
        if len(parts) >= 3:
            src = parts[0].strip().split()[-1].strip("!.,?")
            tgt = parts[2].strip().split()[0].strip("!.,?") if parts[2].strip() else ""
            if src and tgt:
                entities.update([src, tgt])
                relations.append({"source": src, "target": tgt, "type": "IS_A"})
    else:
        for c in candidates:
            entities.add(c)
            relations.append({"source": "User", "target": c, "type": "MENTIONS"})

    return list(entities), relations


def _store_graph(conn: sqlite3.Connection, entities: list[str],
                 relations: list[dict]):
    """Speichere Entitäten und Relationen in SQLite."""
    for ent in entities:
        conn.execute(
            "INSERT OR IGNORE INTO entities (name) VALUES (?);", (ent,)
        )
    for rel in relations:
        conn.execute(
            "INSERT OR IGNORE INTO relations (source, target, rel_type) "
            "VALUES (?, ?, ?);",
            (rel["source"], rel["target"], rel["type"]),
        )


# ---------------------------------------------------------------------------
# Startup Event
# ---------------------------------------------------------------------------

@app.on_event("startup")
def on_startup():
    logger.info("MB-OS Memory Daemon v2.0 startet...")
    _ensure_dirs()
    _init_db()

    # Seed initial memories if DB is empty
    with get_db() as conn:
        count = conn.execute("SELECT COUNT(*) FROM memories;").fetchone()[0]
        if count == 0:
            logger.info("Seed: Initiale Erinnerungen werden eingefügt...")
            seeds = [
                "Der Desktop-Shell hat ein Liquid Glass Design mit verschwommenem Glaseffekt.",
                "Ein HSL-basierter Farbextraktor analysiert das Wallpaper automatisch fürs System-Theme.",
                "Interaktive Micro-Animationen und Lichteffekte folgen dem Mauszeiger auf den Knöpfen.",
                "Das X11 GUI Service-Boot-Problem wurde behoben, indem xinit als Root startet.",
                "Der Memory-Daemon nutzt Markdown-Dateien und SQLite statt PostgreSQL/Neo4j.",
            ]
            for s in seeds:
                cur = conn.execute(
                    "INSERT INTO memories (content, category, source) "
                    "VALUES (?, 'system', 'seed');",
                    (s,),
                )
                _sync_fts_insert(conn, cur.lastrowid, s, "system", "seed")
                _append_to_md(MEMORY_MD, s)

                # Graph-Einträge
                ents, rels = extract_entities_and_relations(s)
                _store_graph(conn, ents, rels)

    logger.info("Memory Daemon bereit. Dateien in: %s", MEMORY_DIR)


# ---------------------------------------------------------------------------
# ENDPOINTS
# ---------------------------------------------------------------------------

# ---- Health ---------------------------------------------------------------

@app.get("/health")
def health():
    """Healthcheck: prüft ob Dateien und DB erreichbar sind."""
    db_ok = DB_PATH.exists()
    md_ok = MEMORY_MD.exists()
    mem_count = 0
    if db_ok:
        try:
            with get_db() as conn:
                mem_count = conn.execute(
                    "SELECT COUNT(*) FROM memories;"
                ).fetchone()[0]
        except Exception:
            db_ok = False

    return {
        "status": "ok" if (db_ok and md_ok) else "degraded",
        "version": "2.0",
        "storage": {
            "memory_dir": str(MEMORY_DIR),
            "db_path": str(DB_PATH),
            "db_ok": db_ok,
            "md_ok": md_ok,
            "memory_count": mem_count,
        },
    }


# ---- Memory Add -----------------------------------------------------------

@app.post("/memory/add")
def add_memory(item: MemoryInput):
    """Speichert neues Wissen in Memory.md + SQLite + Graph."""
    content = item.content.strip()
    if not content:
        raise HTTPException(status_code=400, detail="Content cannot be empty")

    category = (item.category or "").strip()
    source = (item.source or "").strip()

    # 1. In SQLite speichern
    with get_db() as conn:
        cur = conn.execute(
            "INSERT INTO memories (content, category, source) VALUES (?, ?, ?);",
            (content, category, source),
        )
        db_id = cur.lastrowid
        _sync_fts_insert(conn, db_id, content, category, source)

        # 2. Graph-Relationen extrahieren und speichern
        entities, relations = extract_entities_and_relations(content)
        _store_graph(conn, entities, relations)

    # 3. An Memory.md anhängen
    tag = f"[{category}] " if category else ""
    _append_to_md(MEMORY_MD, f"{tag}{content}")

    logger.info("Memory #%d gespeichert: %s", db_id, content[:80])

    return {
        "status": "success",
        "id": db_id,
        "content": content,
        "entities": entities,
        "relations": relations,
    }


# ---- Memory Query ----------------------------------------------------------

@app.post("/memory/query")
def query_memory(item: MemoryQuery):
    """Durchsucht Memories per Volltextsuche (FTS5) + Markdown-Dateien."""
    query = item.query.strip()
    if not query:
        raise HTTPException(status_code=400, detail="Query cannot be empty")

    results = []

    # 1. FTS5-Suche in SQLite
    try:
        with get_db() as conn:
            # FTS5 match mit einfacher Tokenisierung
            # Bereite query für FTS5 vor (Wörter mit OR verknüpfen)
            fts_query = " OR ".join(
                f'"{w}"' for w in query.split() if len(w) > 1
            )
            if fts_query:
                rows = conn.execute(
                    """
                    SELECT m.id, m.content, m.category, m.source, m.created_at,
                           rank
                    FROM memories_fts
                    JOIN memories m ON m.id = memories_fts.rowid
                    WHERE memories_fts MATCH ?
                    ORDER BY rank
                    LIMIT ?;
                    """,
                    (fts_query, item.limit),
                ).fetchall()

                for row in rows:
                    results.append({
                        "id": row["id"],
                        "content": row["content"],
                        "category": row["category"],
                        "source": row["source"],
                        "created_at": row["created_at"],
                        "origin": "sqlite_fts",
                    })
    except Exception as e:
        logger.warning("FTS-Suche fehlgeschlagen: %s — Fallback auf LIKE", e)
        # Fallback: einfache LIKE-Suche
        with get_db() as conn:
            rows = conn.execute(
                "SELECT id, content, category, source, created_at "
                "FROM memories WHERE content LIKE ? LIMIT ?;",
                (f"%{query}%", item.limit),
            ).fetchall()
            for row in rows:
                results.append({
                    "id": row["id"],
                    "content": row["content"],
                    "category": row["category"],
                    "source": row["source"],
                    "created_at": row["created_at"],
                    "origin": "sqlite_like",
                })

    # 2. Zusätzlich Markdown-Dateien durchsuchen (dedupliziert)
    seen_content = {r["content"] for r in results}
    md_results = _search_md_files(query, limit=item.limit)
    for mr in md_results:
        if mr["content"] not in seen_content and len(results) < item.limit:
            results.append({
                "content": mr["content"],
                "file": mr["file"],
                "line": mr["line"],
                "origin": "markdown",
            })
            seen_content.add(mr["content"])

    return {"results": results}


# ---- Memory List -----------------------------------------------------------

@app.get("/memory/list")
def list_memories():
    """Listet alle Memories aus SQLite + alle Skill-Dateien."""
    memories = []
    with get_db() as conn:
        rows = conn.execute(
            "SELECT id, content, category, source, created_at "
            "FROM memories ORDER BY created_at DESC LIMIT 100;"
        ).fetchall()
        for row in rows:
            memories.append({
                "id": row["id"],
                "content": row["content"],
                "category": row["category"],
                "source": row["source"],
                "created_at": row["created_at"],
            })

    # Skills auflisten
    skills = []
    for skill_file in SKILLS_DIR.glob("*.md"):
        text = skill_file.read_text(encoding="utf-8")
        name = skill_file.stem
        # Parse YAML frontmatter wenn vorhanden
        meta = _parse_skill_frontmatter(text)
        skills.append({
            "file": skill_file.name,
            "name": meta.get("name", name),
            "trigger": meta.get("trigger", ""),
            "confidence": meta.get("confidence", ""),
        })

    return {
        "memories": memories,
        "skills": skills,
        "files": {
            "memory_md": str(MEMORY_MD),
            "user_md": str(USER_MD),
            "skills_dir": str(SKILLS_DIR),
        },
    }


# ---- Skills ----------------------------------------------------------------

@app.get("/memory/skills")
def list_skills():
    """Listet alle Skills aus dem Skills/-Verzeichnis."""
    skills = []
    for skill_file in sorted(SKILLS_DIR.glob("*.md")):
        try:
            text = skill_file.read_text(encoding="utf-8")
        except Exception:
            continue
        meta = _parse_skill_frontmatter(text)
        # Extrahiere den Body (alles nach dem zweiten ---)
        body = text
        if text.startswith("---"):
            parts = text.split("---", 2)
            if len(parts) >= 3:
                body = parts[2].strip()

        skills.append({
            "file": skill_file.name,
            "name": meta.get("name", skill_file.stem),
            "trigger": meta.get("trigger", ""),
            "confidence": meta.get("confidence", "medium"),
            "learned_from": meta.get("learned_from", ""),
            "preview": body[:200] if body else "",
        })

    return {"skills": skills, "count": len(skills)}


@app.post("/memory/skills")
def add_skill(item: SkillInput):
    """Erstelle einen neuen Skill als Markdown-Datei."""
    # Sichere Dateinamen generieren
    safe_name = re.sub(r"[^\w\-]", "_", item.name.lower())
    filepath = SKILLS_DIR / f"{safe_name}.md"

    now = datetime.datetime.now().strftime("%Y-%m-%d")
    md_content = (
        f"---\n"
        f"name: {item.name}\n"
        f"trigger: \"{item.trigger}\"\n"
        f"learned_from: {now}\n"
        f"confidence: {item.confidence}\n"
        f"---\n\n"
        f"{item.content}\n"
    )

    filepath.write_text(md_content, encoding="utf-8")
    logger.info("Skill erstellt: %s", filepath)

    return {"status": "success", "file": str(filepath), "name": item.name}


# ---- Graph (für MemoryGraph.qml) ------------------------------------------

@app.get("/memory/graph")
def get_graph():
    """
    Liefert den Wissensgraph als Nodes + Edges.
    Kompatibel mit MemoryGraph.qml (force-directed layout).
    """
    nodes_map: dict[str, dict] = {}
    edges: list[dict] = []

    try:
        with get_db() as conn:
            # Alle Entitäten laden
            for row in conn.execute("SELECT name, entity_type FROM entities;"):
                name = row["name"]
                nodes_map[name] = {
                    "id": name,
                    "label": name,
                    "group": 1 if name == "User" else 2,
                }

            # Alle Relationen laden
            for row in conn.execute(
                "SELECT source, target, rel_type FROM relations LIMIT 200;"
            ):
                src, tgt, rtype = row["source"], row["target"], row["rel_type"]
                # Stelle sicher, dass Quell- und Zielknoten existieren
                if src not in nodes_map:
                    nodes_map[src] = {"id": src, "label": src, "group": 2}
                if tgt not in nodes_map:
                    nodes_map[tgt] = {"id": tgt, "label": tgt, "group": 2}

                edges.append({
                    "source": src,
                    "target": tgt,
                    "type": rtype,
                })
    except Exception as e:
        logger.warning("Graph-Abfrage fehlgeschlagen: %s — gebe Mock zurück", e)
        return _mock_graph()

    # Wenn noch keine Daten vorhanden, Mock-Daten zurückgeben
    if not nodes_map:
        return _mock_graph()

    return {
        "nodes": list(nodes_map.values()),
        "edges": edges,
    }


def _mock_graph() -> dict:
    """Fallback-Graph wenn DB leer oder nicht erreichbar."""
    return {
        "nodes": [
            {"id": "User", "label": "User", "group": 1},
            {"id": "MB-OS", "label": "MB-OS", "group": 2},
            {"id": "Qt6", "label": "Qt6", "group": 2},
            {"id": "Python", "label": "Python", "group": 2},
            {"id": "SQLite", "label": "SQLite", "group": 3},
        ],
        "edges": [
            {"source": "User", "target": "MB-OS", "type": "USES"},
            {"source": "User", "target": "Qt6", "type": "LEARNS"},
            {"source": "User", "target": "Python", "type": "USES"},
            {"source": "MB-OS", "target": "SQLite", "type": "USES"},
        ],
    }


# ---- Sessions --------------------------------------------------------------

@app.post("/sessions/log")
def log_session(item: SessionInput):
    """Logge eine Session in die SQLite-Datenbank."""
    session_id = item.session_id or hashlib.sha256(
        f"{datetime.datetime.now().isoformat()}-{item.summary[:20]}".encode()
    ).hexdigest()[:16]

    topics_json = json.dumps(item.topics or [], ensure_ascii=False)

    with get_db() as conn:
        conn.execute(
            "INSERT OR REPLACE INTO sessions (session_id, summary, topics) "
            "VALUES (?, ?, ?);",
            (session_id, item.summary, topics_json),
        )

    logger.info("Session geloggt: %s", session_id)
    return {"status": "success", "session_id": session_id}


@app.get("/sessions/list")
def list_sessions():
    """Listet alle Sessions auf."""
    with get_db() as conn:
        rows = conn.execute(
            "SELECT session_id, summary, topics, started_at, ended_at "
            "FROM sessions ORDER BY started_at DESC LIMIT 50;"
        ).fetchall()

    sessions = []
    for row in rows:
        sessions.append({
            "session_id": row["session_id"],
            "summary": row["summary"],
            "topics": json.loads(row["topics"]) if row["topics"] else [],
            "started_at": row["started_at"],
            "ended_at": row["ended_at"],
        })

    return {"sessions": sessions, "count": len(sessions)}


# ---- User Profile ----------------------------------------------------------

@app.get("/memory/user")
def get_user_profile():
    """Liefert das Nutzerprofil aus User.md."""
    content = _read_md(USER_MD)
    return {"content": content, "file": str(USER_MD)}


@app.post("/memory/user")
def update_user_profile(item: MemoryInput):
    """Hängt einen Eintrag an User.md an."""
    _append_to_md(USER_MD, item.content.strip())
    return {"status": "success", "content": item.content.strip()}


# ---- Raw Markdown Access ---------------------------------------------------

@app.get("/memory/raw/{filename:path}")
def get_raw_md(filename: str):
    """Lese eine beliebige MD-Datei aus dem Memory-Verzeichnis."""
    filepath = (MEMORY_DIR / filename).resolve()

    # Sicherheitscheck: Datei muss im MEMORY_DIR liegen
    if not str(filepath).startswith(str(MEMORY_DIR.resolve())):
        raise HTTPException(status_code=403, detail="Zugriff verweigert")
    if not filepath.exists():
        raise HTTPException(status_code=404, detail="Datei nicht gefunden")
    if not filepath.suffix == ".md":
        raise HTTPException(status_code=400, detail="Nur .md Dateien erlaubt")

    return {"content": filepath.read_text(encoding="utf-8"), "file": filename}


# ---------------------------------------------------------------------------
# Skill Frontmatter Parser
# ---------------------------------------------------------------------------

def _parse_skill_frontmatter(text: str) -> dict:
    """Parst YAML-Frontmatter aus einer Skill-Datei (einfach, ohne PyYAML)."""
    meta: dict = {}
    if not text.startswith("---"):
        return meta

    parts = text.split("---", 2)
    if len(parts) < 3:
        return meta

    for line in parts[1].strip().splitlines():
        line = line.strip()
        if ":" in line:
            key, _, value = line.partition(":")
            key = key.strip()
            value = value.strip().strip("\"'")
            meta[key] = value

    return meta


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    import uvicorn

    uvicorn.run(
        app,
        host="0.0.0.0",
        port=8000,
        log_level="info",
    )
