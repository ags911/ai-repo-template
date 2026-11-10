from app.application.place_order import place_order
from app.domain.order import OrderRepository


def handle(repo: OrderRepository, order_id: str, quantity: str) -> str:
    place_order(repo, order_id, int(quantity))
    return f"placed {order_id}"
