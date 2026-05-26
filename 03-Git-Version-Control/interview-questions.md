# Git — Interview Questions & Answers

**Q1: What is the difference between `git merge` and `git rebase`?**
> **Merge:** Creates a merge commit, preserves branch history. Safe for public branches.
> **Rebase:** Rewrites commits on top of another branch. Linear history. Never rebase shared/public branches (changes history = force push needed = breaks others' work).
> Rule: Rebase local feature branches, merge into shared branches.

**Q2: What does `git reset`, `git revert`, and `git checkout` do to changes?**
> **git reset:** Moves HEAD (and branch pointer). Three modes:
> - `--soft`: Move HEAD only, keep staging + working dir
> - `--mixed` (default): Move HEAD, clear staging, keep working dir
> - `--hard`: Move HEAD, clear staging AND working dir (DESTRUCTIVE)
> 
> **git revert:** Creates NEW commit that undoes changes. Safe for shared branches. Keeps history.
> 
> **git checkout:** Switches branches OR restores files. Doesn't change commit history.

**Q3: How do you recover a deleted branch?**
```bash
git reflog                          # find the last commit SHA of that branch
git checkout -b recovered-branch abc1234
# or
git checkout -b recovered-branch HEAD@{5}
```

**Q4: How do you squash the last 3 commits?**
```bash
git rebase -i HEAD~3
# Change "pick" to "squash" for commits 2 and 3
# Edit the combined commit message
# Or:
git reset --soft HEAD~3
git commit -m "Combined: new message"
```

**Q5: What is `git stash` and when do you use it?**
> Temporarily saves uncommitted changes (working dir + staging) so you can switch branches. Use when you need to context-switch without losing work and not ready to commit.

**Q6: Explain the Git Flow branching strategy. When would you NOT use it?**
> Git Flow has: `main`, `develop`, `feature/*`, `release/*`, `hotfix/*`.
> Would NOT use for: continuous deployment apps (web services), frequent releases, small teams. TBD or GitHub Flow better for SaaS/CI-CD. Git Flow better for: scheduled releases (mobile apps, packaged software).

**Q7: How do you handle merge conflicts in a large team?**
> Best practices to prevent conflicts:
> 1. Trunk-based development (short-lived branches, merge frequently)
> 2. Own separate files/modules (Conway's law)
> 3. Use feature flags instead of long-lived branches
> 4. When conflict occurs: `git mergetool`, communicate with other dev, understand intent not just code

**Q8: What is `git bisect` and give a scenario where you'd use it?**
> Binary search through commit history to find which commit introduced a bug.
> Scenario: "Performance degraded sometime in last 2 weeks, we have 200 commits. `git bisect run ./perf_test.sh` automates testing each midpoint."

**Q9: How do you enforce commit message standards across a team?**
> 1. Git hooks (pre-commit, commit-msg) — but local, can be bypassed
> 2. Husky + commitlint (Node projects) — harder to bypass
> 3. Server-side hooks (update, pre-receive) — enforced on push
> 4. GitHub branch protection + status checks
> 5. commitizen interactive CLI for formatting

**Q10: Difference between `git fetch` and `git pull`?**
> `git fetch`: Downloads remote changes to remote-tracking branches (origin/main), does NOT modify working directory or local branches.
> `git pull`: `git fetch` + `git merge` (or `git rebase` with `--rebase` flag). Modifies current branch.
> Best practice: `git fetch` then inspect, then merge/rebase manually.

**Q11: How do you find which commit introduced a specific bug (without git bisect)?**
```bash
git log --oneline --all --grep="keyword"    # search commit messages
git log -S "function_name" --source         # search code changes (pickaxe)
git log -G "regex" --all                    # regex search in diffs
git blame path/to/file                      # who changed each line when
git log --follow -- path/to/file            # history across renames
```

**Q12: What are orphan branches and when do you use them?**
> Branches with no common history with main. Created with `git checkout --orphan`.
> Use cases: GitHub Pages (`gh-pages`), versioned documentation, separate deployment configs.

**Q13: How do you set up a Git workflow for microservices in a monorepo?**
> 1. Use sparse checkout to work on relevant services
> 2. Affected CI: only run tests/builds for changed services (Nx/Turborepo/Bazel)
> 3. CODEOWNERS: auto-assign reviewers per service directory
> 4. Path-filtered GitHub Actions:
```yaml
on:
  push:
    paths:
      - 'services/auth/**'
      - 'shared/**'
```
> 5. Semantic versioning per service using tags: `auth/v1.2.3`
