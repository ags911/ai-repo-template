from app.domain.order import OrderRepository, create_order


def place_order(repo: OrderRepository, order_id: str, quantity: int) -> None:
    repo.save(create_order(order_id, quantity))
