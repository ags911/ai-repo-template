import { test } from "node:test";
import assert from "node:assert/strict";
import { createOrder } from "./order.ts";

test("createOrder rejects non-positive quantities", () => {
  assert.throws(() => createOrder("o-1", 0));
  assert.deepEqual(createOrder("o-1", 2), { id: "o-1", quantity: 2 });
});
