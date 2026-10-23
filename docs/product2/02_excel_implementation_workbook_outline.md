# Excel Implementation Workbook — Outline
A real .xlsx version of this should be built with the xlsx skill once an organization's actual data is in hand. This file defines its required tabs so that build is a formatting pass, not a design pass.

## Tab 1 — Teams & Divisions
Columns: Division | Team Name | Coach | Team Parent | Player Count (auto)

## Tab 2 — Job Role Matrix
Columns: Role Name | Category (org/team) | Earns Org Credit (Y/N) | Hours Credited | Volunteers Needed | Background Check Required | Training Required | Verifier Role

## Tab 3 — Standard Home Game Template
Columns: Role Name | Volunteers Needed | Arrival Offset (min)
One row per role; this tab is the direct source for `job_template_item` rows.

## Tab 4 — Season Config Values
Columns: Setting | Value | Notes
Rows: hours_per_child, fundraising_goal_per_child, replacement_fee_amount, no_show_fee_amount, no_show_grace_period_days, share_credit_amount, share_credit_board_approved

## Tab 5 — Family/Player Roster (if migrating from spreadsheets rather than self-registration)
Columns: Family Display Name | Guardian 1 Name | Guardian 1 Email | Guardian 2 Name (optional) | Player Full Name | Division | Team | Jersey Number

## Tab 6 — Uniform Sizes (if collected outside self-registration)
Columns: Player Full Name | Jersey Size | Pant Size | Prior Year Jersey Size
