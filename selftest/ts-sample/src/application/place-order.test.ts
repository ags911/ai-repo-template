import { test } from "node:test";
import assert from "node:assert/strict";
import type { Order, OrderRepository } from "../domain/order.ts";
import { placeOrder } from "./place-order.ts";

test("placeOrder saves the order", () => {
  const saved: Order[] = [];
  const repo: OrderRepository = { save: (order) => saved.push(order) };
  placeOrder(repo, "o-1", 3);
  assert.deepEqual(saved, [{ id: "o-1", quantity: 3 }]);
});
