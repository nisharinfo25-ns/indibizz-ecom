import test from "node:test";
import assert from "node:assert/strict";
import { formatMoney, formatMoneyCompact, formatDate, pluralize } from "../src/format";

test("formatMoney uses paise without floating point drift", () => {
  assert.match(formatMoney(129900), /1,299/);
  assert.match(formatMoney(129950), /1,299\.50/);
  assert.match(formatMoney(0), /0/);
});

test("formatMoneyCompact omits unnecessary decimals", () => {
  assert.match(formatMoneyCompact(50000), /500/);
  assert.doesNotMatch(formatMoneyCompact(50000), /\.00/);
});

test("formatDate handles null and invalid values", () => {
  assert.equal(formatDate(null), "—");
  assert.equal(formatDate("not-a-date"), "—");
  assert.match(formatDate("2026-01-15T10:00:00Z"), /2026/);
});

test("pluralize handles singular and plural", () => {
  assert.equal(pluralize(1, "item"), "item");
  assert.equal(pluralize(2, "item"), "items");
  assert.equal(pluralize(2, "parcel", "parcels"), "parcels");
});
