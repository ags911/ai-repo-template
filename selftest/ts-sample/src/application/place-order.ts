import { createOrder, type OrderRepository } from "../domain/order.ts";

export function placeOrder(repo: OrderRepository, id: string, quantity: number): void {
  repo.save(createOrder(id, quantity));
}
