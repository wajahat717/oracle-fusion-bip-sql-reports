# Oracle Fusion Cloud BI Publisher (BIP) SQL Reports

Production SQL data models I built and debugged for Oracle Fusion Cloud BI Publisher, covering **Payables, Receivables, Project Billing (PPM), Subledger Accounting (XLA)** and the **Enterprise Scheduler (ESS)**.

Every query here ran against a live Fusion Cloud pod and was checked against the source system or the General Ledger before delivery.

---

## Reports

### 1. AP Aging built from Subledger Accounting — `ap_aging_from_subledger/`
**Problem:** The old AP aging report was built from invoice tables only, so it did not tie to the AP liability accounts on the Balance Sheet. It missed payments made before the invoice was accounted, payment requests, prepayment applications, and anything older than a 60-month window.

**Solution:** Rebuilt the report on the same source Oracle's Supplier Balance report uses: Payables accounting entries (`XLA_AE_HEADERS`, `XLA_AE_LINES`, `XLA_DISTRIBUTION_LINKS`) on the LIABILITY accounting class, as of a chosen date. Each accounting line is traced back to its invoice through invoice distributions, payment distributions or prepayment applications, then netted and aged into buckets.

**Result:** The aging total tied to the GL AP accounts within a small rounding difference, while keeping the exact same 18 output columns so the existing Excel layout still worked.

**Key lesson:** `XLA_TRANSACTION_ENTITIES` is a secured view and returns zero rows inside a BIP data model. I found this with a step-by-step row-count funnel and replaced it with joins through the distribution tables.

### 2. AR Aging with PO number and "emailed to" — `ar_aging_with_po_and_email/`
**Problem:** The collections team needed to see which PO each invoice used and who it was emailed to, without breaking the original report their Excel macros depended on.

**Solution:** An extended version of the original query: the same columns and logic first, then new columns at the end. The "emailed to" value is chosen in priority order: invoice-level recipients (`DEL_CONTACT_EMAIL_ADDRESS`), then the bill-to contact, then the site default. A second column, `EMAILED_TO_SOURCE`, tells the user which one was used, and shows "Not Sent" when the invoice was never printed or emailed.

### 3. Scheduled jobs and their email recipients — `scheduled_jobs_email_recipients/`
**Problem:** Nobody could answer "who receives which scheduled report?" The BIP scheduler tables (`XMLP_SCHED_*`) are blocked for cloud customers (ORA-01031).

**Solution:** Read the Enterprise Scheduler tables instead (`ESS_REQUEST_HISTORY`, `ESS_REQUEST_PROPERTY`), pivot the job properties, and pull every email address out of the delivery XML with `REGEXP_SUBSTR` + `CONNECT BY`. Filters by report name and "active jobs only". Oracle's own "From" address is excluded.

### 4. Unbilled revenue reconciliation — `unbilled_revenue_reconciliation/`
**Problem:** Finance needed to net billed revenue (Receivables) against recognised revenue (Projects) by GL account, journal batch, contract and project. The Receivables half of the report returned no rows at all.

**Solution:** A `UNION ALL` of two branches. The Receivables branch was rebuilt to reach the AR transaction through `XLA_DISTRIBUTION_LINKS`, **collapsed to one row per accounting line** to stop fan-out, and to take contract and project from `PJB_XLA_INV_HEAD_REF_V`.

**Key lesson:** My first fix joined the distribution links directly and the rows nearly tripled, with debits no longer equal to credits. Grouping the links by `AE_HEADER_ID, AE_LINE_NUM` before joining fixed it, and debits matched credits to the cent.

### 5. Reusable snippets — `reusable_snippets/`
- `bip_parameter_patterns.sql` — the "All" parameter pattern, safe handling of BIP date parameters, and keeping only the current row from history tables
- `business_days_between_dates.sql` — working-day count that does not depend on session language
- `gl_location_hierarchy_cte.sql` — turns a GL location tree into location → region

---

## BIP lessons I apply on every build

| Problem | What I do |
|---|---|
| `--` comments break the query (BIP joins lines, so a comment swallows the rest of the SQL, giving ORA-00907) | No `--` anywhere, not even inside `/* */` blocks |
| Trailing semicolon | Never end a data set query with `;` |
| Reserved words as aliases (`SIZE`) give ORA-00923 | Quote them: `AS "Size"` |
| EBS column names that do not exist in Fusion (ORA-00904) | Check `ALL_TAB_COLUMNS` before writing a join |
| BIP preview shows only 200 rows by default | Use aggregates or raise the row limit before drawing conclusions |
| Joins that multiply rows (fan-out) | Compare row counts and DR = CR before and after every join |
| Effective-dated or translated tables duplicate keys | Filter to the current row and one language |

## Tools

Oracle Fusion Cloud · BI Publisher data models · Oracle SQL (CTEs, analytic functions, `LISTAGG`, `REGEXP`, `KEEP DENSE_RANK`) · Subledger Accounting (XLA)

> All client names, people, IDs and amounts have been removed. Custom lookup codes are replaced with generic names.
