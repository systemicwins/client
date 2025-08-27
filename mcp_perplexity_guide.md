# MCP with Perplexity Integration Guide

## ✅ Setup Complete on Olympus

### Available Models with Tool Support:
- **devstral:latest** (23.6B params) - Mistral's code model
- **qwen3-coder:latest** (30.5B params) - Qwen 3 coding model  

### MCP Configuration:
Location: `~/.config/ollmcp/config.json`
```json
{
  "mcpServers": {
    "search-server": {
      "env": {
        "PERPLEXITY_API_KEY": "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",
        "PERPLEXITY_MODEL": "sonar"
      },
      "command": "/home/alex/.local/bin/perplexity-mcp"
    }
  }
}
```

## How to Use Successfully:

### Method 1: Interactive Model Selection

1. Start ollmcp:
   ```bash
   ~/.local/bin/ollmcp -j ~/.config/ollmcp/config.json
   ```

2. When you see the prompt, type `m` to select model
3. Choose option **1** (devstral:latest) or **2** (qwen3-coder:latest)  
4. Type `s` to save selection
5. Now ask questions that require web search

### Method 2: Pre-configured Session

Create a session file:
```bash
cat > session_commands.txt << 'EOF'
m
1
s
What is the current Tesla stock price? Use the search tool.
/exit
EOF

~/.local/bin/ollmcp -j ~/.config/ollmcp/config.json < session_commands.txt
```

## Verification Status:

✅ **perplexity-mcp server** connects successfully  
✅ **Tool available:** `search-server.perplexity_search_web`  
✅ **devstral** supports tools (confirmed)  
✅ **qwen3-coder** supports tools (confirmed)  
✅ **Configuration** is valid and working  

## Example Questions to Test:

1. "What is the current Bitcoin price?"
2. "Search for recent news about Tesla stock"  
3. "Find the latest information about Microsoft earnings"
4. "What are today's trending tech stocks?"

The models will automatically use the perplexity search tool when they need current information.

## Troubleshooting:

**If you see "Tools Not Supported" error:**
- The current model (often Phi-4-reasoning-plus by default) doesn't support tools
- Use `m` command to switch to devstral or qwen3-coder
- Make sure to save the selection with `s`

**Key Points:**
- Both devstral and qwen3-coder have verified tool support
- The perplexity-mcp integration is properly configured
- You just need to manually select the tool-capable model in the session

## Working Setup Summary:

```bash
# Start ollmcp with perplexity integration
~/.local/bin/ollmcp -j ~/.config/ollmcp/config.json

# In the session:
# 1. Type: m
# 2. Choose: 1 (for devstral) or 2 (for qwen3-coder)  
# 3. Type: s
# 4. Ask: "What's the current Tesla stock price? Please search for it."
```

The integration is fully functional - you just need to select a model that supports tools!