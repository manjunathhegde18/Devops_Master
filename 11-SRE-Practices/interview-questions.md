# SRE Practices — Interview Questions & Answers

**Q1: Explain SLI, SLO, and SLA with concrete examples.**
> **SLI**: The metric you measure. "99.2% of checkout API requests completed in < 500ms and returned HTTP < 500 over the last 28 days."
> **SLO**: Your internal target. "We will maintain 99.5% availability and 99% of requests < 500ms."
> **SLA**: Your contractual promise to customers. "We guarantee 99% uptime; below this triggers service credits."
>
> Relationship: SLA ≤ SLO (internal target must be harder than customer promise to leave buffer).
> Setting SLOs: measure user satisfaction, find the threshold below which users complain, set SLO just above that.

---

**Q2: What is an error budget and how does it change team behavior?**
> Error budget is the maximum allowed unreliability: `1 - SLO`. For a 99.9% SLO = 43.8 min/month of allowed downtime.
>
> Impact on behavior:
> - **Development teams** want to ship fast; SREs want stability. Error budget is the shared arbiter.
> - Plenty of budget → deploy, experiment, take risks. Budget is the runway.
> - Budget running low → slow down risky changes, prioritize reliability work.
> - Budget exhausted → feature freeze until next period; SRE team stops new feature support and focuses on reliability.
>
> It transforms the conversation from "ops blocking dev" to "both teams share the same budget and make tradeoff decisions together."

---

**Q3: How do you define SLOs for a new service?**
> 1. **Instrument first**: Add the four golden signals metrics before setting targets
> 2. **Measure baseline**: What is current actual availability/latency?
> 3. **Define good**: What does "working correctly for users" mean for this service?
> 4. **User research**: What threshold of degradation causes users to abandon or complain?
> 5. **Set SLO slightly below baseline**: Don't target perfection — start conservative
> 6. **Review quarterly**: Tighten as reliability improves; loosen if consistently over-achieving
>
> Common mistake: setting SLOs at 99.99% without measuring whether that's achievable or even necessary.

---

**Q4: Walk through how you would run a blameless post-mortem.**
> 1. **Timeline building (within 24h)**: Gather all data — logs, metrics, pager alerts, Slack threads, actions taken. Create objective timeline without assigning fault.
> 2. **Meeting (48-72h)**: Invite all involved. IC, engineers, on-call. Facilitator is neutral (often senior SRE not involved in incident).
> 3. **Focus**: What failed? Not who failed. "The process allowed X" not "Alice didn't do X."
> 4. **5 Whys**: Drill to systemic root cause. Usually: missing automation, missing alert, missing test, missing documentation.
> 5. **Action items**: Specific, assigned, time-bound. Not vague like "improve monitoring." Instead: "Add alert for DB connection pool > 80% — assigned to Bob — due June 1."
> 6. **Publish**: Share widely. Learning is only valuable when spread.

---

**Q5: What is toil and how do you measure and reduce it?**
> Toil is manual, repetitive, automatable operational work that scales with service growth and has no lasting value.
>
> **Measuring**: Time tracking per task category over 2-4 weeks. Ask: how long did each operational task take this week?
>
> **Reducing**:
> - Manual DB restarts → health check + auto-restart (livenessProbe or systemd Restart=always)
> - Certificate renewals → cert-manager
> - Disk fills → alerting at 80% + auto-expansion or cleanup cron
> - Manual deploys → CI/CD pipeline
>
> Goal: < 50% of SRE time on toil. If more, the team is an ops team in SRE clothing.

---

**Q6: How do you design a system for 99.99% availability?**
> First: understand that 99.99% = 52 minutes/year downtime. This is extremely hard to achieve.
>
> Requirements:
> - **Multi-AZ deployment**: No single data center failure takes down the service
> - **Zero-downtime deployments**: Rolling updates with maxUnavailable: 0
> - **Fast auto-healing**: HPA + Cluster Autoscaler, liveness probes with automatic restart
> - **Fast detection**: P99 alert fires in < 2 minutes of degradation
> - **Fast recovery**: MTTR < 10 minutes requires runbooks, automation, practiced incidents
> - **Database HA**: Aurora (sub-30s failover), multi-AZ RDS, read replicas
> - **Circuit breakers**: Prevent cascade failures from one service taking down others
> - **Chaos testing**: Regularly inject failures to find hidden dependencies
>
> Reality check: Most services don't need 99.99%. 99.9% (43 min/month) is right for most B2B; 99.5% is fine for many internal tools.

---

**Q7: Explain the difference between MTTR, MTTD, MTTF, and MTBF.**
> - **MTTD (Mean Time to Detect)**: Avg time from failure occurrence to detection. Goal: minimize with better alerting. Target: < 2 min.
> - **MTTR (Mean Time to Recover/Repair)**: Avg time from detection to restoration. Reduced by runbooks, automation, practiced response. Target: < 30 min for SEV-1.
> - **MTTF (Mean Time to Failure)**: Avg time a system operates before failing. For hardware/non-repairable items.
> - **MTBF (Mean Time Between Failures)**: For repairable systems. MTTF + MTTR. Higher is better.
>
> **Availability formula**: MTBF / (MTBF + MTTR) × 100%

---

**Q8: How do you approach on-call rotations and prevent burnout?**
> Structure:
> - Maximum coverage: 1 week primary + 1 week secondary per rotation
> - No more than 2 on-call weeks per quarter per person
> - Compensation: On-call differential pay, time-off after heavy weeks
>
> Preventing alert fatigue:
> - Review all pages weekly: "should this have paged?"
> - Delete or demote alerts that required no action 3 times in a row
> - Mean time between pages target: > 2 hours
> - Only page when human action is immediately required
>
> If on-call is miserable: fix the product, not the rotation. Persistent bad on-call = product has fundamental reliability issues.

---

**Q9: What is chaos engineering and how do you introduce it responsibly?**
> Chaos engineering deliberately injects failures into production (or staging) to discover weaknesses before they cause incidents.
>
> **Responsible introduction**:
> 1. Start in staging/canary — never directly in production until team is comfortable
> 2. Define steady state before experimenting (dashboards ready, team watching)
> 3. Start small: kill 1 pod, not the whole deployment
> 4. Always have an abort procedure
> 5. Run during business hours with team present (not at 3am)
> 6. GameDay events: structured, scheduled, everyone informed
>
> **Graduated rollout**:
> - Week 1: Kill a single pod, confirm auto-restart
> - Week 2: Kill all pods in one AZ, confirm multi-AZ failover
> - Week 3: Inject 100ms latency to database, confirm circuit breaker
> - Month 2: Full region failover test

---

**Q10: Tell me about a major incident you handled. (Behavioral)**
> Structure your answer using the SRE incident framework:
>
> **S** (Situation): "We had a SEV-1 — payment service returning 503 for 35% of requests."
> **T** (Task): "I was the IC on call. MTTR target was 30 minutes, SLO breach threshold was 10 min."
> **A** (Action):
> 1. Opened incident channel, assigned roles
> 2. Checked dashboards — DB connection pool at 99%
> 3. Identified long-running transactions from recent deployment
> 4. Rolled back deployment via CI/CD in 8 minutes
> 5. Confirmed recovery, communicated to stakeholders
> **R** (Result): "Restored service in 22 minutes. Post-mortem identified missing query index. Added automated slow-query gate to CI."
>
> Always end with: what you changed to prevent recurrence.
