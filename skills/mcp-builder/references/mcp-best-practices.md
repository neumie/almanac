# MCP Best Practices

## Tool Design

- **One tool per operation**: Avoid multi-purpose tools. `create_issue` and `list_issues` are better than `manage_issues`.
- **Consistent naming**: Use `{service}_{action}_{resource}` pattern. E.g., `github_create_issue`, `slack_send_message`.
- **Input validation**: Use Zod (TypeScript) or Pydantic (Python) for all inputs. Include constraints and descriptions.
- **Output schemas**: Define `outputSchema` when returning structured data. Helps clients parse responses.

## Error Handling

- Return actionable error messages: "API key expired. Run `export API_KEY=...` to update." not "Auth failed."
- Distinguish between user errors (bad input) and server errors (API down)
- Include the original error when wrapping exceptions

## Pagination

- Support `limit` and `offset` or `cursor` parameters
- Return `hasMore` indicator and `nextCursor` when applicable
- Default to reasonable page sizes (20-50 items)

## Authentication

- Support environment variables for API keys
- Document required env vars in README
- Validate credentials on first use, not at startup

## Performance

- Use async/await for all I/O operations
- Implement request timeouts
- Cache responses when appropriate (especially for metadata)
- Batch related API calls where possible
