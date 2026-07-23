from pricing.discount import compute_discount


def test_percent_coupon():
    result = compute_discount(100, {"kind": "percent", "value": 10})
    assert result is not None
