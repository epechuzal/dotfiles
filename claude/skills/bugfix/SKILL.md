# Bugfix: Diagnose Before Fixing

You are investigating a bug. Follow this sequence strictly — do NOT skip steps or jump to implementing a fix.

## Step 1: Trace the actual data/control flow

Before hypothesizing about the cause, read the relevant source files and trace what actually happens:
- For data display bugs: trace DB query → ORM entity → serialization → API response → frontend render
- For logic bugs: trace the input through each transformation step
- For CI/CD bugs: read the actual error output and trace it to the source

Use Task agents to explore if the scope is unclear. Present your findings as a numbered data flow.

## Step 2: Write a failing test

Write a test that reproduces the exact bug — run it and confirm it fails for the right reason. If you cannot reproduce the bug in a test, stop and say so rather than guessing.

## Step 3: Present diagnosis and wait

Present:
- **Root cause:** one sentence explaining why the bug happens
- **Evidence:** the specific line(s) or data transformation where behavior diverges from expected
- **Proposed fix:** what you plan to change and why

**STOP and wait for user confirmation before proceeding.** Do not implement anything yet.

## Step 4: Implement and verify

After user confirms the diagnosis:
1. Implement the fix
2. Run the failing test — confirm it passes
3. Run the full test suite for affected projects
4. Only create a commit after all tests pass

If any test fails, iterate on the fix — do not ask the user unless your original diagnosis was wrong.
