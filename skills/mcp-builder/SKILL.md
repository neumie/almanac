---
name: mcp-builder
description: Use when building MCP (Model Context Protocol) servers to integrate external APIs or services. Guides implementation in TypeScript or Python with proper tool design, error handling, and testing. Use this whenever the user mentions MCP, building tools for LLMs, or integrating external services.
metadata:
  upstream: anthropics/skills/mcp-builder
  upstream-sha: 8a1a77a47d141967b246adb4da4f91037578ff7d
  adapted-date: "2026-03-09"
---

# MCP Server Development

Create MCP servers that enable LLMs to interact with external services through well-designed tools.

## High-Level Workflow

### Phase 1: Research and Planning

**Understand the API:**
- Review the service's API documentation
- Identify key endpoints, auth requirements, and data models
- Use web search and WebFetch as needed

**Study MCP docs:**
- Start with the sitemap: `https://modelcontextprotocol.io/sitemap.xml`
- Fetch pages with `.md` suffix for markdown format
- Review: specification, transport mechanisms, tool/resource/prompt definitions

**Load framework docs:**
- See [references/mcp-best-practices.md](references/mcp-best-practices.md) for core guidelines
- See [references/typescript-guide.md](references/typescript-guide.md) for TypeScript patterns
- See [references/python-guide.md](references/python-guide.md) for Python patterns

**Recommended stack:**
- TypeScript with MCP SDK (best compatibility)
- Streamable HTTP for remote servers, stdio for local
- Zod for input validation

**Plan tool coverage:**
- Prioritize comprehensive API coverage over workflow shortcuts
- List endpoints to implement, starting with most common operations
- Use consistent naming prefixes (e.g., `github_create_issue`, `github_list_repos`)

### Phase 2: Implementation

**Set up project structure** per language-specific guide.

**Core infrastructure:**
- API client with authentication
- Error handling with actionable messages
- Response formatting (JSON/Markdown)
- Pagination support

**For each tool, implement:**
- Input schema (Zod for TypeScript, Pydantic for Python)
- Clear tool description
- Async/await for I/O operations
- Proper error handling with suggestions for resolution
- Pagination where applicable
- Tool annotations: `readOnlyHint`, `destructiveHint`, `idempotentHint`

### Phase 3: Review and Test

- No duplicated code (DRY)
- Consistent error handling
- Full type coverage
- Clear tool descriptions
- Test with MCP Inspector: `npx @modelcontextprotocol/inspector`

### Phase 4: Documentation

- README with setup instructions
- Authentication configuration
- Available tools with descriptions
- Example usage

## Key Design Principles

**Actionable error messages:** Guide agents toward solutions with specific suggestions and next steps.

**Context management:** Return focused, relevant data. Support filtering and pagination.

**Tool naming:** Clear, descriptive, consistent prefixes. Action-oriented.

**Progressive disclosure:** Simple tools for common cases, detailed tools for advanced use.
