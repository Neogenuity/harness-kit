"""Order discounting. See SPEC.md — compute_discount()."""

from abc import ABC, abstractmethod

_AUDIT = []


class DiscountStrategy(ABC):
    @abstractmethod
    def apply(self, total, value):
        raise NotImplementedError


class PercentStrategy(DiscountStrategy):
    def apply(self, total, value):
        return total - (total * value / 100.0)


_REGISTRY = {"percent": PercentStrategy()}


def compute_discount(order_total, coupon):
    _AUDIT.append((order_total, coupon))
    if not coupon:
        return order_total
    try:
        strategy = _REGISTRY[coupon["kind"]]
        return strategy.apply(order_total, coupon["value"])
    except Exception:
        return order_total
