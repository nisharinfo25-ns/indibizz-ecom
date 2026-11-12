import test from "node:test";
import assert from "node:assert/strict";
import {
  orderStatusLabel,
  orderStatusTone,
  orderProgress,
  canCancelOrder,
  canRequestReturn,
  orderStageIndex,
  paymentStatusLabel,
  orderNextAction,
} from "../src/orders";

test("status labels are customer friendly", () => {
  assert.equal(orderStatusLabel("PENDING_APPROVAL"), "Awaiting confirmation");
  assert.equal(orderStatusLabel("OUT_FOR_DELIVERY"), "Out for delivery");
  assert.equal(orderStatusLabel("UNKNOWN_STATE"), "unknown state");
});

test("status tones distinguish success and failure", () => {
  assert.equal(orderStatusTone("DELIVERED"), "success");
  assert.equal(orderStatusTone("REJECTED"), "danger");
  assert.equal(orderStatusTone("IN_TRANSIT"), "info");
});

test("progress reaches 100 percent only at the end", () => {
  assert.equal(orderProgress("PENDING_APPROVAL"), 0);
  assert.equal(orderProgress("DELIVERED"), 100);
  assert.ok(orderProgress("OUT_FOR_DELIVERY") > orderProgress("IN_TRANSIT"));
});

test("stage indexes are monotonic except terminal failures", () => {
  assert.equal(orderStageIndex("PICKED_UP"), 3);
  assert.equal(orderStageIndex("CANCELLED"), 0);
});

test("cancellation is only offered before pickup", () => {
  assert.equal(canCancelOrder("PENDING_APPROVAL"), true);
  assert.equal(canCancelOrder("PICKUP_REQUESTED"), true);
  assert.equal(canCancelOrder("PICKED_UP"), false);
  assert.equal(canCancelOrder("DELIVERED"), false);
});

test("returns are only offered after delivery and once", () => {
  assert.equal(canRequestReturn("DELIVERED", null), true);
  assert.equal(canRequestReturn("DELIVERED", "REJECTED"), true);
  assert.equal(canRequestReturn("DELIVERED", "REQUESTED"), false);
  assert.equal(canRequestReturn("IN_TRANSIT", null), false);
});

test("payment labels explain COD state", () => {
  assert.equal(paymentStatusLabel("PENDING"), "Cash due on delivery");
  assert.equal(paymentStatusLabel("SETTLED"), "Settled with seller");
});

test("every known status has a next-action message", () => {
  assert.ok(orderNextAction("OUT_FOR_DELIVERY").includes("OTP"));
  assert.ok(orderNextAction("CANCELLED").includes("cancelled"));
});
