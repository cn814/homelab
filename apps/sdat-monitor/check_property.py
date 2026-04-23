#!/usr/bin/env python3
import os
import json
import logging
import smtplib
import requests
from email.mime.text import MIMEText
from datetime import datetime

logging.basicConfig(level=logging.INFO, format='%(asctime)s %(message)s')
log = logging.getLogger(__name__)

# Maryland Open Data SODA API — Howard County Real Property Assessments
# Dataset: https://opendata.maryland.gov/resource/9t52-zebk
# Note: owner names are hidden in this dataset; we monitor deed reference + transfer data instead
SODA_URL = "https://opendata.maryland.gov/resource/9t52-zebk.json"

# Properties to monitor: (premise_number, premise_street_name, display_address)
PROPERTIES = [
    ("10141", "BELL INN",   "10141 Bell Inn Ln, Ellicott City"),
    ("10030", "WHITWORTH",  "10030 Whitworth Way, Ellicott City"),
]

# SODA field names (verbatim from API)
F_PREM_NUM  = "premise_address_number_mdp_field_premsnum_sdat_field_20"
F_PREM_NAME = "premise_address_name_mdp_field_premsnam_sdat_field_23"
F_DR_LIBER  = "deed_reference_1_liber_mdp_field_dr1liber_sdat_field_30"
F_DR_FOLIO  = "deed_reference_1_folio_mdp_field_dr1folio_sdat_field_31"
F_GRANTOR   = "sales_segment_1_grantor_name_mdp_field_grntnam1_sdat_field_80"
F_TRADATE   = "sales_segment_1_transfer_date_yyyy_mm_dd_mdp_field_tradate_sdat_field_89"
F_PRICE     = "sales_segment_1_consideration_mdp_field_considr1_sdat_field_90"
F_ACCTID    = "account_id_mdp_field_acctid"

STATE_FILE = "/data/last_state.json"
EMAIL_FROM = os.environ.get("EMAIL_FROM", "cnealen@gmail.com")
EMAIL_TO   = os.environ.get("EMAIL_TO",   "cnealen@gmail.com")
EMAIL_PASS = os.environ.get("EMAIL_PASS", "")


def fetch_property(prem_num, prem_name, display_addr):
    params = {
        F_PREM_NUM:  prem_num,
        F_PREM_NAME: prem_name,
        "$limit": "5",
    }
    resp = requests.get(SODA_URL, params=params, timeout=30)
    resp.raise_for_status()
    rows = resp.json()

    if not rows:
        raise ValueError(f"No records found for {display_addr} — check PREM_NUM/PREM_NAME")
    if len(rows) > 1:
        log.warning(f"Multiple records returned for {display_addr} ({len(rows)}), using first")

    row = rows[0]
    liber = row.get(F_DR_LIBER, "").strip()
    folio = row.get(F_DR_FOLIO, "").strip()

    return {
        "acctid":     row.get(F_ACCTID, "").strip(),
        "deed_ref":   f"{liber}/{folio}" if (liber or folio) else None,
        "grantor":    row.get(F_GRANTOR, "").strip() or None,
        "tradate":    row.get(F_TRADATE, "").strip() or None,
        "sale_price": row.get(F_PRICE,   "").strip() or None,
        "checked_at": datetime.now().isoformat(),
    }


def load_state():
    if os.path.exists(STATE_FILE):
        with open(STATE_FILE) as f:
            return json.load(f)
    return {}


def save_state(state):
    os.makedirs(os.path.dirname(STATE_FILE), exist_ok=True)
    with open(STATE_FILE, "w") as f:
        json.dump(state, f, indent=2)


def notify(title, message):
    try:
        msg = MIMEText(message)
        msg["Subject"] = title
        msg["From"]    = EMAIL_FROM
        msg["To"]      = EMAIL_TO
        with smtplib.SMTP_SSL("smtp.gmail.com", 465) as smtp:
            smtp.login(EMAIL_FROM, EMAIL_PASS)
            smtp.sendmail(EMAIL_FROM, EMAIL_TO, msg.as_string())
        log.info(f"Notification sent: {title}")
    except Exception as e:
        log.error(f"Notification failed: {e}")


def check_one(prem_num, prem_name, display_addr, state):
    log.info(f"Checking {display_addr}...")
    try:
        current = fetch_property(prem_num, prem_name, display_addr)
    except Exception as e:
        log.error(f"Failed to fetch {display_addr}: {e}")
        return state

    log.info(
        f"  Account: {current['acctid']} | Deed: {current['deed_ref']} | "
        f"Grantor: {current['grantor']} | Transfer: {current['tradate']} | Price: {current['sale_price']}"
    )

    key = current["acctid"] or f"{prem_num}_{prem_name}"
    previous = state.get(key, {})

    if not previous:
        log.info(f"  No previous state for {display_addr} — saving baseline.")
        state[key] = current
        return state

    changed = False

    if previous.get("deed_ref") != current["deed_ref"]:
        log.warning(f"  DEED CHANGED: {previous['deed_ref']} -> {current['deed_ref']}")
        notify(
            f"Deed changed: {display_addr}",
            (
                f"Property: {display_addr}\n"
                f"New deed reference: {current['deed_ref']}\n"
                f"Previous deed reference: {previous['deed_ref']}\n"
                f"Last known grantor (seller): {current['grantor']}\n"
                f"Transfer date: {current['tradate']}\n"
                f"Sale price: {current['sale_price']}\n"
                f"Check SDAT for current owner: https://sdat.dat.maryland.gov/RealProperty/Pages/default.aspx"
            ),
        )
        changed = True

    elif previous.get("tradate") != current["tradate"]:
        log.warning(f"  TRANSFER DATE CHANGED: {previous['tradate']} -> {current['tradate']}")
        notify(
            f"Transfer date changed: {display_addr}",
            (
                f"Property: {display_addr}\n"
                f"New transfer date: {current['tradate']}\n"
                f"Grantor: {current['grantor']}\n"
                f"Sale price: {current['sale_price']}\n"
                f"Deed reference: {current['deed_ref']}\n"
                f"Check SDAT for current owner: https://sdat.dat.maryland.gov/RealProperty/Pages/default.aspx"
            ),
        )
        changed = True

    if changed:
        state[key] = current
    else:
        log.info(f"  No change detected.")
        state[key]["checked_at"] = current["checked_at"]

    return state


def main():
    state = load_state()
    for prem_num, prem_name, display_addr in PROPERTIES:
        state = check_one(prem_num, prem_name, display_addr, state)
    save_state(state)


if __name__ == "__main__":
    main()
