from app.domain.order import Order


class InMemoryOrderRepository:
    def __init__(self) -> None:
        self.orders: list[Order] = []

    def save(self, order: Order) -> None:
        self.orders.append(order)
