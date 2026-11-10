import pytest

from app.application.place_order import place_order
from app.domain.order import Order, create_order


class FakeRepository:
    def __init__(self) -> None:
        self.saved: list[Order] = []

    def save(self, order: Order) -> None:
        self.saved.append(order)


def test_create_order_rejects_non_positive_quantity() -> None:
    with pytest.raises(ValueError):
        create_order("o-1", 0)


def test_place_order_saves_the_order() -> None:
    repo = FakeRepository()
    place_order(repo, "o-1", 3)
    assert repo.saved == [Order("o-1", 3)]
