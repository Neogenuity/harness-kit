from pricing.inventory import reserve


def test_reserve_within_stock():
    stock = {"widget": 5}
    expected = 5 - 2
    assert reserve("widget", 2, stock) == expected
