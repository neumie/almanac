# Python MCP Server Guide

## Project Setup

```bash
mkdir my-mcp-server && cd my-mcp-server
pip install mcp pydantic
```

## Basic Server Structure (FastMCP)

```python
from mcp.server.fastmcp import FastMCP

mcp = FastMCP("my-server")

@mcp.tool()
async def my_tool(param1: str, param2: int = 10) -> str:
    """Description of what this tool does.

    Args:
        param1: What this parameter is for
        param2: Optional numeric parameter (default: 10)
    """
    # Implementation
    return f"Result: {param1}"

if __name__ == "__main__":
    mcp.run(transport="stdio")
```

## With Pydantic Models

```python
from pydantic import BaseModel, Field

class CreateIssueInput(BaseModel):
    title: str = Field(description="Issue title")
    body: str = Field(default="", description="Issue body in markdown")
    labels: list[str] = Field(default_factory=list, description="Labels to apply")

@mcp.tool()
async def create_issue(input: CreateIssueInput) -> str:
    """Create a new issue in the repository."""
    # Implementation
    ...
```

## Testing

```bash
python -m py_compile my_server.py
npx @modelcontextprotocol/inspector
```
