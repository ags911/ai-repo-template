import type { Order, OrderRepository } from "../domain/order.ts";

export class InMemoryOrderRepository implements OrderRepository {
  readonly orders: Order[] = [];
  save(order: Order): void {
    this.orders.push(order);
  }
}
