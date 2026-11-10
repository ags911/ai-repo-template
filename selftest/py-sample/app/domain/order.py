from dataclasses import dataclass
from typing import Protocol


@dataclass(frozen=True)
class Order:
    id: str
    quantity: int


class OrderRepository(Protocol):
    """Repository interface: defined in domain, implemented in infrastructure."""

    def save(self, order: Order) -> None: ...


def create_order(order_id: str, quantity: int) -> Order:
    if quantity <= 0:
        raise ValueError("quantity must be positive")
    return Order(order_id, quantity)
