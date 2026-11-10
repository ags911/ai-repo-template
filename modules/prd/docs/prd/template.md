# PRD: Feature name

## Summary
What and why, in two or three sentences. Which module or context it touches.

## Acceptance criteria
- [ ] **AC-01:** Given <state>, when <action>, then <outcome>.
- [ ] **AC-02:** Given <invalid input>, when <action>, then <specific error>.

## Data contract
```json
{
  "type": "object",
  "required": ["id", "amount"],
  "properties": {
    "id": { "type": "string", "format": "uuid" },
    "amount": { "type": "integer", "minimum": 1 }
  }
}
```

## Constraints
- New dependencies: (allowed / need an ADR / none)
- Out of scope:

## Verification
Each acceptance criterion maps to at least one test. List the test paths here when done.
