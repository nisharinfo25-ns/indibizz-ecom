"""End-to-end database integration tests for IndiaBizz Phase 1 (COD).

Runs against a throwaway embedded PostgreSQL with Supabase-compatible shims.
Covers the complete order -> pickup -> delivery -> COD -> settlement path,
cancellation, returns, immutable evidence, OTP failure semantics and RLS.

Run: python supabase/tests/integration_test.py
"""
from __future__ import annotations

import sys
import tempfile
import traceback
from pathlib import Path

import psycopg
from psycopg.types.json import Jsonb

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))

from db_harness import DB, apply_migrations  # noqa: E402

PASSED: list[str] = []


def check(name: str, condition: bool, detail: str = "") -> None:
    if not condition:
        raise AssertionError(f"{name} failed. {detail}")
    PASSED.append(name)
    print(f"  PASS  {name}")


def expect_raises(name: str, db: DB, sql: str, params: tuple = (), contains: str | None = None) -> None:
    try:
        db.one(sql, params)
    except psycopg.Error as exc:
        message = str(exc)
        if contains and contains.lower() not in message.lower():
            raise AssertionError(f"{name}: expected error containing {contains!r}, got: {message}") from exc
        PASSED.append(name)
        print(f"  PASS  {name}")
        return
    raise AssertionError(f"{name}: expected an error but the call succeeded")


def run(db: DB) -> None:
    print("Setup: users, roles, catalogue, logistics coverage")
    owner = db.make_user("+919000000001", "Owner")
    customer = db.make_user("+919000000002", "Customer")
    staff = db.make_user("+919000000003", "Ravi Kumar")
    stranger = db.make_user("+919000000004", "Stranger")

    db.privileged()
    db.execute("update public.profiles set role = 'OWNER' where id = %s", (owner,))
    db.reset()

    # Owner configuration -----------------------------------------------------
    db.as_user(owner)
    town = db.call("owner_save_town", "Chennai", "Chennai", "Tamil Nadu", 13.0827, 80.2707, True, None)
    town_id = town["id"]
    db.call("owner_add_serviceable_pincode", town_id, "600001", True)
    settings = db.call(
        "owner_update_settings",
        Jsonb({
            "business": {
                "legal_name": "IndiaBizz Retail Private Limited",
                "display_name": "IndiaBizz",
                "address": "12 Market Road, Chennai 600001",
                "phone": "+919000000001",
                "email": "orders@indibizz.test",
                "gstin": "",
                "support_phone": "+919000000001",
                "support_email": "support@indibizz.test",
                "timezone": "UTC",
                "invoice_terms": "COD only. Returns within 7 days.",
                "pickup_town_id": town_id,
                "pickup_pincode": "600001",
            },
            "commerce": {
                "tax_enabled": False,
                "default_tax_rate_bps": 0,
                "shipping_fee_paise": 4900,
                "free_shipping_threshold_paise": 100000,
            },
            "policies": {"cancellation_allowed_before_pickup": True, "return_window_days": 7},
            "logistics": {"auto_create_delivery_assignment": True, "require_photo": True, "max_delivery_attempts": 3},
        }),
    )
    check("owner settings saved", settings["business"]["legal_name"].startswith("IndiaBizz Retail"))

    category = db.call("owner_save_category", "Kitchen", "kitchen", "Kitchen essentials", None, 1, True, None)
    product = db.call(
        "owner_save_product", category["id"], "Steel Water Bottle", "BTL-001", 25000, 0, "7323",
        "1 litre insulated steel bottle", None, 500, "ACTIVE", True, 3, 10, None, None,
    )
    product_id = product["id"]
    check("product created with opening stock", product["quantity_on_hand"] == 10)
    check("public catalogue setting readable", db.one("select count(*) from public.products where status='ACTIVE'") == 1)

    # Staff onboarding --------------------------------------------------------
    invite = db.call("owner_create_staff_invite", "+919000000003", "OWN_DELIVERY_STAFF", "Ravi Kumar", None, False)
    check("staff invite created", len(invite["activation_code"]) == 10)

    db.as_user(staff)
    redeemed = db.call("redeem_staff_invite", invite["activation_code"])
    check("staff invite redeemed", redeemed["role"] == "OWN_DELIVERY_STAFF")
    expect_raises("invite cannot be redeemed twice", db, "select public.redeem_staff_invite(%s)", (invite["activation_code"],), "already provisioned")

    db.as_user(owner)
    db.call("owner_set_staff_coverage", staff, Jsonb([{"town_id": town_id, "pincode": None}]))
    check("staff coverage saved", db.one("select count(*) from public.staff_service_areas where staff_user_id=%s", (staff,)) == 1)

    # Customer order ----------------------------------------------------------
    db.as_user(customer)
    address = db.call(
        "save_my_address", "Home", "Customer", "+919000000002", "5 Beach Road", "Near Park", "Blue gate",
        town_id, "600001", True, None,
    )
    check("address saved", address["pincode"] == "600001")
    check("serviceability check passes", db.call("check_serviceability", "600001", town_id)["serviceable"] is True)
    db.call("cart_add_item", product_id, 2)
    quote = db.call("quote_my_order", address["id"])
    expected_total = quote["subtotal_paise"] + quote["shipping_paise"] + quote["tax_paise"] - quote["discount_paise"]
    check("quote total is coherent", quote["total_paise"] == expected_total, str(quote))

    order = db.call("place_order", address["id"], "idem-checkout-0001", "Deliver after 5pm")
    order_id = order["order_id"]
    check("order placed as COD pending approval", order["status"] == "PENDING_APPROVAL" and order["cod_amount_paise"] == expected_total)
    replay = db.call("place_order", address["id"], "idem-checkout-0001", "Deliver after 5pm")
    check("checkout is idempotent", replay["order_id"] == order_id and replay["idempotent_replay"] is True)
    db.privileged()
    check("stock reserved on checkout", db.one("select quantity_reserved from public.inventory where product_id=%s", (product_id,)) == 2)

    # Owner approval, packaging, pickup OTP ----------------------------------
    db.as_user(owner)
    approved = db.call("approve_order", order_id, 2)
    shipment_id = approved["shipment_id"]
    check("order approved with invoice", approved["invoice_number"].startswith("INV-"))
    admin = db.call("owner_get_order_admin", order_id)
    check("two packages generated", len(admin["packages_detail"]) == 2)
    for pkg in admin["packages_detail"]:
        db.call("owner_seal_package", pkg["id"])
    ready = db.call("owner_mark_ready_for_pickup", order_id)
    check("order ready for pickup", ready["status"] == "READY_FOR_PICKUP")
    pickup = db.call("owner_request_pickup", order_id)
    pickup_id = pickup["pickup_id"]
    pickup_otp = pickup["otp"]
    check("pickup OTP issued to owner only", isinstance(pickup_otp, str) and len(pickup_otp) == 6)

    # Assignment --------------------------------------------------------------
    assignment_id = None
    admin = db.call("owner_get_order_admin", order_id)
    if admin.get("pickup") and admin["pickup"].get("assignment"):
        assignment_id = admin["pickup"]["assignment"]["id"]
        check("pickup auto-assigned to eligible staff", admin["pickup"]["assignment"]["mode"] == "AUTO")
    else:
        assigned = db.call("owner_assign_pickup", pickup_id, staff, "Manual fallback in test")
        assignment_id = assigned["assignment_id"]
        check("pickup manually assigned", bool(assignment_id))
    check("customer never receives pickup OTP", db.as_user(customer) or db.one(
        "select count(*) from public.notifications where recipient_id=%s and type='PICKUP_OTP'", (customer,)
    ) == 0)

    # Delivery staff pickup ---------------------------------------------------
    db.as_user(staff)
    detail = db.call("staff_get_pickup", assignment_id)
    check("staff sees sealed package codes", len(detail["packages"]) == 2)
    packages = detail["packages"]

    db.call("staff_accept_pickup", assignment_id)
    db.call("staff_arrive_at_pickup", assignment_id, 13.0827, 80.2707)
    bad_scan = db.call("staff_scan_package", assignment_id, "NOT-A-PACKAGE", "scan-bad-0001", 13.0827, 80.2707, "dev-test")
    check("unknown barcode rejected", bad_scan["result"] == "INVALID_CODE")

    for index, pkg in enumerate(packages):
        scan = db.call(
            "staff_scan_package", assignment_id, pkg["package_code"],
            f"scan-good-{index}-0001", 13.0827, 80.2707, "dev-test",
        )
        check(f"package {index + 1} scanned", scan["result"] == "VALID")
    dup = db.call("staff_scan_package", assignment_id, packages[0]["package_code"], "scan-dup-0001", 13.0827, 80.2707, "dev-test")
    check("duplicate scan flagged", dup["result"] == "DUPLICATE")

    check(
        "barcode scans alone never mark PICKED_UP",
        db.one("select status::text from public.shipments where id=%s", (shipment_id,)) != "PICKED_UP"
        and db.one("select status::text from public.orders where id=%s", (order_id,)) not in ("PICKED_UP", "IN_TRANSIT"),
    )
    wrong = db.call("staff_verify_pickup", assignment_id, "000000", 2, "GOOD", "wrong otp")
    check("wrong pickup OTP rejected", wrong["ok"] is False and wrong["error_code"] == "INVALID_OTP")
    expect_raises(
        "wrong package count is rejected", db,
        "select public.staff_verify_pickup(%s,%s,%s,%s,%s)",
        (assignment_id, pickup_otp, 1, "GOOD", "wrong count"), "does not match",
    )
    db.privileged()
    db.execute("update public.pickup_otp_challenges set attempts = max_attempts where pickup_request_id=%s", (pickup_id,))
    db.as_user(staff)
    locked = db.call("staff_verify_pickup", assignment_id, pickup_otp, 2, "GOOD", "locked")
    check("locked pickup OTP reports lock state", locked["ok"] is False and locked["error_code"] == "OTP_LOCKED")
    db.privileged()
    db.execute("update public.pickup_otp_challenges set attempts = 0 where pickup_request_id=%s", (pickup_id,))
    db.as_user(staff)
    verified = db.call("staff_verify_pickup", assignment_id, pickup_otp, 2, "GOOD", "checked")
    check("pickup verified with OTP and count", verified["ok"] is True and verified["shipment_status"] == "PICKED_UP")
    delivery_assignment_id = verified.get("delivery_assignment_id")
    check("delivery assignment created for same staff", delivery_assignment_id is not None)
    check("shipment locked as picked up", db.one("select status from public.shipments where id=%s", (shipment_id,)) == "PICKED_UP")

    # Delivery ----------------------------------------------------------------
    db.as_user(staff)
    db.call("staff_accept_delivery", delivery_assignment_id)
    db.call("staff_mark_in_transit", delivery_assignment_id, 13.05, 80.25)
    db.call("staff_mark_arrived_at_destination", delivery_assignment_id, 13.0827, 80.2707)
    out = db.call("staff_start_out_for_delivery", delivery_assignment_id)
    check("delivery out for delivery", out["shipment_status"] == "OUT_FOR_DELIVERY")
    check("delivery OTP is not returned to staff app", "otp" not in out)
    expect_raises(
        "wrong COD amount is refused", db,
        "select public.staff_complete_delivery(%s,%s,%s,%s,%s,%s,%s,%s)",
        (delivery_assignment_id, "000000", "Customer", "note", None, 13.0, 80.2, 1),
        "COD amount",
    )

    db.as_user(customer)
    tracking = db.call("get_order_tracking", order_id)
    delivery_otp = tracking.get("delivery_otp")
    check("customer receives structured delivery OTP", isinstance(delivery_otp, str) and len(delivery_otp) == 6)
    check("customer tracking shows out for delivery", tracking["shipment_status"] == "OUT_FOR_DELIVERY")

    db.as_user(staff)
    bad = db.call("staff_complete_delivery", delivery_assignment_id, "000000", "Customer", "wrong otp", None, 13.0, 80.2, order["cod_amount_paise"])
    check("wrong delivery OTP rejected", bad["ok"] is False and bad["error_code"] == "INVALID_OTP")
    photo_path = f"{shipment_id}/doorstep.jpg"
    done = db.call(
        "staff_complete_delivery", delivery_assignment_id, delivery_otp, "Customer", "Handed over",
        photo_path, 13.0, 80.2, order["cod_amount_paise"],
    )
    check("delivery completed with OTP", done["ok"] is True and done["shipment_status"] == "DELIVERED")
    check("COD marked collected", done["payment_status"] == "COLLECTED")
    check("delivery proof recorded", db.one("select count(*) from public.delivery_proofs where shipment_id=%s", (shipment_id,)) == 1)
    check(
        "COD ledger has expected and collected entries",
        db.one(
            "select count(*) from public.cod_transactions where shipment_id=%s and entry_type in ('EXPECTED','COLLECTED')",
            (shipment_id,),
        ) == 2,
    )
    check(
        "shipment history is append-only",
        db.one("select count(*) from public.shipment_events where shipment_id=%s and event_type='DELIVERED'", (shipment_id,)) == 1,
    )
    db.as_service()
    expect_raises(
        "shipment events cannot be deleted even by service role", db,
        "delete from public.shipment_events where shipment_id=%s", (shipment_id,), "immutable",
    )
    expect_raises(
        "COD ledger cannot be edited even by service role", db,
        "update public.cod_transactions set amount_paise=1 where shipment_id=%s", (shipment_id,), "immutable",
    )
    db.as_user(staff)

    # COD handover and owner verification ------------------------------------
    summary = db.call("staff_cod_summary")
    check("staff cash custody reflects collection", summary["cash_in_custody_paise"] == order["cod_amount_paise"])
    handover = db.call("staff_declare_cash_handover", "End of day handover")
    settlement_id = handover["settlement_id"]
    check("handover declared", handover["handed_over_paise"] == order["cod_amount_paise"])

    db.as_user(owner)
    settlements = db.call("owner_list_cod_settlements", "PENDING_VERIFICATION")
    check("owner sees pending settlement", any(s["id"] == settlement_id for s in settlements))
    verified_settlement = db.call("owner_confirm_cod_settlement", settlement_id, order["cod_amount_paise"], "Counted")
    check("settlement verified", verified_settlement["status"] == "VERIFIED")
    check("order payment marked settled", db.one("select payment_status from public.orders where id=%s", (order_id,)) == "SETTLED")

    # Return flow -------------------------------------------------------------
    db.as_user(customer)
    ret = db.call("request_return", order_id, "DAMAGED", "Bottle dented on arrival", None)
    return_id = ret["return_id"]
    check("return requested within window", ret["status"] == "REQUESTED")

    db.as_user(owner)
    decided = db.call("owner_decide_return", return_id, True, "Approved after review")
    check("return approved", decided["status"] == "APPROVED")
    received = db.call("owner_mark_return_received", return_id, True, "Restocked")
    check("return received", received["status"] == "RECEIVED")
    closed = db.call("owner_close_return", return_id, "Refund settled offline")
    check("return closed", closed["status"] == "CLOSED")
    db.privileged()
    check("returned stock restocked", db.one("select quantity_on_hand from public.inventory where product_id=%s", (product_id,)) == 10)

    # Cancellation releases reservation --------------------------------------
    db.as_user(customer)
    db.call("cart_add_item", product_id, 3)
    second = db.call("place_order", address["id"], "idem-checkout-0002", None)
    db.privileged()
    check("second order reserved stock", db.one("select quantity_reserved from public.inventory where product_id=%s", (product_id,)) == 3)
    db.as_user(customer)
    cancelled = db.call("cancel_order", second["order_id"], "Ordered by mistake")
    check("pending order cancelled", cancelled["status"] == "CANCELLED")
    db.privileged()
    check("cancellation released reservation", db.one("select quantity_reserved from public.inventory where product_id=%s", (product_id,)) == 0)

    # Security / RLS ----------------------------------------------------------
    db.as_user(stranger)
    check("stranger cannot read another customer's orders", db.one("select count(*) from public.orders") == 0)
    check("stranger cannot read customer addresses", db.one("select count(*) from public.addresses") == 0)
    expect_raises("stranger cannot call owner dashboard", db, "select public.owner_dashboard()", (), "owner")
    expect_raises("customer cannot call staff dashboard", db, "select public.staff_dashboard()", (), "staff")
    expect_raises(
        "clients cannot write orders directly", db,
        "insert into public.orders (order_number, customer_id, subtotal_paise, tax_paise, shipping_paise, total_paise, cod_amount_paise, item_count, address_id, recipient_name, phone, line1, town_id, town_name, district, state, pincode, idempotency_key) "
        "values ('HACK-1', %s, 1,0,0,1,1,1,%s,'x','+919000000002','x',%s,'x','x','x','600001','hack-0000001')",
        (stranger, address["id"], town_id), "permission denied",
    )
    db.reset()
    expect_raises(
        "profile role guard blocks direct SQL", db,
        "update public.profiles set role='OWNER' where id=%s", (stranger,), "authorized server operation",
    )
    db.as_user(stranger)
    expect_raises(
        "owner RPC rejects customer role", db, "select public.owner_get_settings()", (), "owner authorization",
    )

    db.as_anon()
    check("anon can read active catalogue", db.one("select count(*) from public.products where status='ACTIVE'") == 1)
    expect_raises("anon cannot read orders", db, "select count(*) from public.orders", (), "permission denied")
    expect_raises("anon cannot execute owner RPC", db, "select public.owner_dashboard()", (), "permission denied")

    db.as_service()
    check("service role can list profiles for workers", db.one("select count(*) from public.profiles") >= 4)
    check("public settings seeded", db.one("select count(*) from public.app_settings") >= 4)


def main() -> int:
    print("Starting embedded PostgreSQL...")
    srv, db = DB.start(data_dir=tempfile.mkdtemp(prefix="ib_pg_it_"), cleanup_mode="delete")
    try:
        apply_migrations(db.conn)
        print("Migrations applied. Running scenarios...\n")
        run(db)
        print(f"\nSUCCESS: {len(PASSED)} checks passed.")
        return 0
    except Exception:
        print(f"\nFAILURE after {len(PASSED)} checks:")
        traceback.print_exc()
        return 1
    finally:
        db.conn.close()


if __name__ == "__main__":
    raise SystemExit(main())
