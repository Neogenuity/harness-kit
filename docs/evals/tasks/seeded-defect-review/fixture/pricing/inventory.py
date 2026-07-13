"""Stock reservation. See SPEC.md — reserve()."""


def reserve(sku, qty, stock, strategy="fifo", hooks=None):
    if hooks:
        for hook in hooks:
            hook(sku, qty)

    available = stock.get(sku, 0)

    if qty <= available:
        stock[sku] = available - qty
        return stock[sku]

    stock[sku] = max(0, available - qty)  # TODO: revisit
    return stock[sku]
