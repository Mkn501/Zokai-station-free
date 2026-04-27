import { createServer } from "./server.js";
import { SSEServerTransport } from "@modelcontextprotocol/sdk/server/sse.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import express from "express";

async function main() {
    const transport = process.env.MCP_TRANSPORT || "sse";
    const port = parseInt(process.env.PORT || "8012", 10);

    const server = createServer();

    if (transport === "stdio") {
        console.error("Starting Markdownify MCP with STDIO transport...");
        const stdioTransport = new StdioServerTransport();
        await server.connect(stdioTransport);
    } else if (transport === "sse") {
        console.error(`Starting Markdownify MCP with SSE transport on port ${port}...`);

        const app = express();

        // Health check endpoint
        app.get("/health", (req, res) => {
            res.json({ status: "healthy", service: "markdownify-mcp" });
        });

        // SSE endpoint
        let sseTransport: SSEServerTransport | null = null;

        app.get("/sse", async (req, res) => {
            console.error("SSE connection established");
            sseTransport = new SSEServerTransport("/message", res);
            await server.connect(sseTransport);
        });

        app.post("/message", async (req, res) => {
            if (sseTransport) {
                await sseTransport.handlePostMessage(req, res);
            } else {
                res.status(400).json({ error: "No SSE connection established" });
            }
        });

        app.listen(port, "0.0.0.0", () => {
            console.error(`Markdownify MCP Server listening on http://0.0.0.0:${port}`);
            console.error(`SSE endpoint: http://0.0.0.0:${port}/sse`);
            console.error(`Health check: http://0.0.0.0:${port}/health`);
        });
    } else {
        console.error(`Unsupported transport: ${transport}`);
        process.exit(1);
    }
}

main().catch((error) => {
    console.error("Fatal error:", error);
    process.exit(1);
});
