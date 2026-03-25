"""
test_alert_engine.py
--------------------
Unit tests for the FinOps alert classification logic.
Run: python -m pytest tests/ -v
"""

import sys, os, tempfile
sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))

import pytest
from src.alert_engine import classify_risk, compute_overage_cost
from src.config import ServiceLimit


# ── Risk Classification Tests ──────────────────────────────────────────────────
class TestClassifyRisk:
    def test_safe_below_70(self):
        assert classify_risk(0.0)   == "SAFE"
        assert classify_risk(50.0)  == "SAFE"
        assert classify_risk(69.99) == "SAFE"

    def test_at_risk_70_to_99(self):
        assert classify_risk(70.0)  == "AT-RISK"
        assert classify_risk(85.0)  == "AT-RISK"
        assert classify_risk(99.99) == "AT-RISK"

    def test_breach_100_and_above(self):
        assert classify_risk(100.0) == "BREACH"
        assert classify_risk(120.0) == "BREACH"
        assert classify_risk(200.0) == "BREACH"

    def test_boundary_exact_values(self):
        assert classify_risk(70.00) == "AT-RISK"
        assert classify_risk(100.0) == "BREACH"


# ── Overage Cost Tests ─────────────────────────────────────────────────────────
class TestComputeOverageCost:
    def _make_svc(self, limit, cost_per_unit):
        return ServiceLimit(
            service_name="Test Service",
            service_key="TestSvc",
            monthly_limit=limit,
            unit="GB",
            cost_per_unit=cost_per_unit,
            category="test",
        )

    def test_no_overage_within_limit(self):
        svc = self._make_svc(limit=5.0, cost_per_unit=0.023)
        assert compute_overage_cost(svc, 4.99) == 0.0
        assert compute_overage_cost(svc, 5.0)  == 0.0

    def test_overage_calculated_correctly(self):
        svc = self._make_svc(limit=5.0, cost_per_unit=0.023)
        # 6 GB projected: 1 GB over limit at $0.023/GB
        result = compute_overage_cost(svc, 6.0)
        assert abs(result - 0.023) < 0.0001

    def test_large_overage(self):
        svc = self._make_svc(limit=750, cost_per_unit=0.0116)
        # EC2: 900 hrs projected → 150 hrs over → $1.74
        result = compute_overage_cost(svc, 900)
        assert abs(result - (150 * 0.0116)) < 0.0001

    def test_zero_usage(self):
        svc = self._make_svc(limit=5.0, cost_per_unit=0.023)
        assert compute_overage_cost(svc, 0.0) == 0.0


# ── Projection Logic Tests ─────────────────────────────────────────────────────
class TestProjectionLogic:
    """Test the core projection formula: projected = mtd * (30 / day_of_month)"""

    def test_projection_mid_month(self):
        # Day 15 of month, 375 EC2 hours used → projects to 750 (exactly 100%)
        day = 15
        mtd = 375.0
        limit = 750.0
        proj_factor = 30 / day
        projected = mtd * proj_factor
        pct = (projected / limit) * 100
        assert abs(pct - 100.0) < 0.001
        assert classify_risk(pct) == "BREACH"

    def test_projection_early_month_safe(self):
        # Day 5: only 50 EC2 hours (on track for 300/750 = 40%) → SAFE
        day = 5
        mtd = 50.0
        limit = 750.0
        proj_factor = 30 / day
        projected = mtd * proj_factor
        pct = (projected / limit) * 100
        assert pct < 70
        assert classify_risk(pct) == "SAFE"

    def test_projection_end_of_month(self):
        # Day 28: 690 hours → projects to ~739 / 750 = 98.5% → AT-RISK
        day = 28
        mtd = 690.0
        limit = 750.0
        proj_factor = 30 / day
        projected = mtd * proj_factor
        pct = (projected / limit) * 100
        assert 70 <= pct < 100
        assert classify_risk(pct) == "AT-RISK"


# ── Free Tier Config Tests ─────────────────────────────────────────────────────
class TestFreeTierConfig:
    def test_all_services_have_required_fields(self):
        from src.config import FREE_TIER_LIMITS
        for key, svc in FREE_TIER_LIMITS.items():
            assert svc.service_name,   f"{key}: missing service_name"
            assert svc.monthly_limit > 0, f"{key}: monthly_limit must be positive"
            assert svc.unit,           f"{key}: missing unit"
            assert svc.cost_per_unit >= 0, f"{key}: cost_per_unit cannot be negative"
            assert svc.category,       f"{key}: missing category"

    def test_ec2_limit(self):
        from src.config import FREE_TIER_LIMITS
        ec2 = FREE_TIER_LIMITS["AmazonEC2"]
        assert ec2.monthly_limit == 750
        assert ec2.unit == "Hrs"

    def test_s3_limit(self):
        from src.config import FREE_TIER_LIMITS
        s3 = FREE_TIER_LIMITS["AmazonS3"]
        assert s3.monthly_limit == 5.0
        assert s3.unit == "GB"

    def test_lambda_limit(self):
        from src.config import FREE_TIER_LIMITS
        lam = FREE_TIER_LIMITS["AWSLambda"]
        assert lam.monthly_limit == 1_000_000


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
