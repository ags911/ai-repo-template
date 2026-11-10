export interface Order {
  id: string;
  quantity: number;
}

/** Repository interface: defined in domain, implemented in infrastructure. */
export interface OrderRepository {
  save(order: Order): void;
}

export function createOrder(id: string, quantity: number): Order {
  if (quantity <= 0) throw new Error("quantity must be positive");
  return { id, quantity };
}
