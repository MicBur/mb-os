import QtQuick

Item {
    id: root
    width: 400
    height: 400

    property var nodes: []
    property var edges: []
    property var draggedNode: null

    // Force-directed layout physics parameters
    property double repulsion: 800.0
    property double springLength: 80.0
    property double springK: 0.04
    property double gravity: 0.03
    property double damping: 0.90

    // Fetch graph data from memory daemon API
    function refreshGraph() {
        var xhr = new XMLHttpRequest();
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                if (xhr.status === 200) {
                    try {
                        var data = JSON.parse(xhr.responseText);
                        updateGraphData(data.nodes, data.edges);
                    } catch (e) {
                        console.log("Error parsing graph JSON:", e);
                    }
                }
            }
        }
        xhr.open("GET", "http://localhost:8000/memory/graph");
        xhr.send();
    }

    function updateGraphData(newNodes, newEdges) {
        // Keep positions of existing nodes to prevent jumpiness
        var nodeMap = {};
        for (var i = 0; i < nodes.length; i++) {
            nodeMap[nodes[i].id] = nodes[i];
        }

        var initializedNodes = [];
        for (var j = 0; j < newNodes.length; j++) {
            var n = newNodes[j];
            if (nodeMap[n.id]) {
                // Keep existing position
                nodeMap[n.id].label = n.label;
                nodeMap[n.id].group = n.group;
                initializedNodes.push(nodeMap[n.id]);
            } else {
                // Initialize random position near center
                n.x = root.width / 2 + (Math.random() - 0.5) * 100;
                n.y = root.height / 2 + (Math.random() - 0.5) * 100;
                n.vx = 0.0;
                n.vy = 0.0;
                initializedNodes.push(n);
            }
        }

        nodes = initializedNodes;
        edges = newEdges;
    }

    // Timer running at 60fps for physics simulation
    Timer {
        id: simTimer
        interval: 16
        running: true
        repeat: true
        onTriggered: {
            if (nodes.length === 0) return;
            physicsStep();
            canvas.requestPaint();
        }
    }

    // Run one step of the force-directed layout simulation
    function physicsStep() {
        var cx = root.width / 2;
        var cy = root.height / 2;

        // 1. Repulsion between all node pairs (Coulomb's Law)
        for (var i = 0; i < nodes.length; i++) {
            var n1 = nodes[i];
            if (n1 === draggedNode) continue;

            for (var j = 0; j < nodes.length; j++) {
                if (i === j) continue;
                var n2 = nodes[j];

                var dx = n1.x - n2.x;
                var dy = n1.y - n2.y;
                var distSq = dx * dx + dy * dy;
                if (distSq < 10) distSq = 10; // Avoid division by zero
                var dist = Math.sqrt(distSq);

                // Force is inversely proportional to distance squared
                var f = repulsion / distSq;
                n1.vx += (dx / dist) * f;
                n1.vy += (dy / dist) * f;
            }
        }

        // 2. Attraction along edges (Hooke's Law / Springs)
        // Map nodes for fast lookup
        var nodeMap = {};
        for (var k = 0; k < nodes.length; k++) {
            nodeMap[nodes[k].id] = nodes[k];
        }

        for (var e = 0; e < edges.length; e++) {
            var edge = edges[e];
            var source = nodeMap[edge.source];
            var target = nodeMap[edge.target];

            if (!source || !target) continue;

            var sdx = target.x - source.x;
            var sdy = target.y - source.y;
            var sdist = Math.sqrt(sdx * sdx + sdy * sdy);
            if (sdist < 1) sdist = 1;

            var forceAmount = springK * (sdist - springLength);
            var fx = (sdx / sdist) * forceAmount;
            var fy = (sdy / sdist) * forceAmount;

            if (source !== draggedNode) {
                source.vx += fx;
                source.vy += fy;
            }
            if (target !== draggedNode) {
                target.vx -= fx;
                target.vy -= fy;
            }
        }

        // 3. Gravity pulling towards center and integration of velocities
        for (var m = 0; m < nodes.length; m++) {
            var node = nodes[m];
            if (node === draggedNode) continue;

            // Gravity force
            var gdx = cx - node.x;
            var gdy = cy - node.y;
            node.vx += gdx * gravity;
            node.vy += gdy * gravity;

            // Apply velocity with damping
            node.x += node.vx;
            node.y += node.vy;
            node.vx *= damping;
            node.vy *= damping;

            // Bound node positions to canvas size
            if (node.x < 20) node.x = 20;
            if (node.x > root.width - 20) node.x = root.width - 20;
            if (node.y < 20) node.y = 20;
            if (node.y > root.height - 20) node.y = root.height - 20;
        }
    }

    // Canvas to draw nodes and edges
    Canvas {
        id: canvas
        anchors.fill: parent
        renderTarget: Canvas.Image

        onPaint: {
            var ctx = canvas.getContext("2d");
            ctx.clearRect(0, 0, width, height);

            // 1. Draw Edges (Links)
            ctx.lineWidth = 1.5;
            ctx.strokeStyle = themeManager.secondaryColor + "50"; // Glowing theme accent line

            // Build node positions mapping for quick access
            var nodeMap = {};
            for (var i = 0; i < nodes.length; i++) {
                nodeMap[nodes[i].id] = nodes[i];
            }

            for (var j = 0; j < edges.length; j++) {
                var edge = edges[j];
                var s = nodeMap[edge.source];
                var t = nodeMap[edge.target];
                if (s && t) {
                    ctx.beginPath();
                    ctx.moveTo(s.x, s.y);
                    ctx.lineTo(t.x, t.y);
                    ctx.stroke();

                    // Optional: Draw text label of relationship in middle
                    ctx.fillStyle = "#80a5c0";
                    ctx.font = "8px sans-serif";
                    ctx.fillText(edge.type, (s.x + t.x)/2, (s.y + t.y)/2);
                }
            }

            // 2. Draw Nodes (Entities)
            for (var k = 0; k < nodes.length; k++) {
                var n = nodes[k];

                // Glowing outer ring on hover/selected or just general glow
                ctx.beginPath();
                ctx.arc(n.x, n.y, 14, 0, 2 * Math.PI);
                ctx.fillStyle = n.group === 1 ? themeManager.accentColor + "30" : themeManager.secondaryColor + "30"; // Theme accents fill
                ctx.fill();
                ctx.lineWidth = 2;
                ctx.strokeStyle = n.group === 1 ? themeManager.accentColor : themeManager.secondaryColor; // Neon theme accents border
                ctx.stroke();

                // Inner dot
                ctx.beginPath();
                ctx.arc(n.x, n.y, 6, 0, 2 * Math.PI);
                ctx.fillStyle = "#ffffff";
                ctx.fill();

                // Labels
                ctx.fillStyle = "#ffffff";
                ctx.font = "bold 10px sans-serif";
                ctx.textAlign = "center";
                ctx.fillText(n.label, n.x, n.y - 18);
            }
        }
    }

    // Mouse area for node dragging interaction
    MouseArea {
        anchors.fill: parent
        onPressed: (mouse) => {
            // Find closest node to click
            var clickRadius = 25.0;
            var closest = null;
            var minDist = clickRadius;

            for (var i = 0; i < nodes.length; i++) {
                var n = nodes[i];
                var dx = n.x - mouse.x;
                var dy = n.y - mouse.y;
                var d = Math.sqrt(dx*dx + dy*dy);
                if (d < minDist) {
                    minDist = d;
                    closest = n;
                }
            }

            if (closest) {
                draggedNode = closest;
                draggedNode.vx = 0;
                draggedNode.vy = 0;
            }
        }

        onPositionChanged: (mouse) => {
            if (draggedNode) {
                draggedNode.x = mouse.x;
                draggedNode.y = mouse.y;
            }
        }

        onReleased: {
            draggedNode = null;
        }
    }

    Component.onCompleted: {
        // Fetch initially and then set up a periodic poll every 5 seconds to get updates
        refreshGraph();
    }

    Timer {
        interval: 5000
        running: true
        repeat: true
        onTriggered: refreshGraph()
    }
}
