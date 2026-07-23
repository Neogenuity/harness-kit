# Feature spec — the change under review

Two small, pure helpers were requested. This is the intended scope the reviewer
must hold the diff against.

## `pricing/discount.py`

Add `compute_discount(order_total, coupon)` that returns the discounted total:

- a percent coupon (e.g. `{"kind": "percent", "value": 10}`) reduces the total
  by that percent;
- an unknown or `None` coupon is a no-op — return `order_total` unchanged.

It must be a **pure function**: no I/O, no printing, no module-global state.

## `pricing/inventory.py`

Add `reserve(sku, qty, stock)` that returns the **new stock level** for `sku`
after reserving `qty` units. If `qty` exceeds the available stock, raise
`ValueError`. It must operate on a **copy** of the passed-in `stock` mapping —
the caller's dict must not be mutated.

## Tests

Add `tests/test_discount.py` and `tests/test_inventory.py` that pin the
behaviour above, including the no-op path and the `ValueError` path.
