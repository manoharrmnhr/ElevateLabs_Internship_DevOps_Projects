/* main.js — CloudStatic (v1) */
'use strict';

(function () {
  /* ── Deploy timestamp ──────────────────────────────────── */
  const ts = document.getElementById('deploy-ts');
  if (ts) ts.textContent = new Date().toLocaleString('en-IN', {
    dateStyle: 'medium', timeStyle: 'short'
  });

  /* ── Navbar scroll shadow ──────────────────────────────── */
  const navbar = document.querySelector('.navbar');
  window.addEventListener('scroll', () => {
    navbar?.classList.toggle('navbar--scrolled', window.scrollY > 20);
  }, { passive: true });

  /* ── Smooth reveal on scroll ───────────────────────────── */
  const items = document.querySelectorAll('.arch-card, .pipeline-step, .stack-card');
  if ('IntersectionObserver' in window) {
    const io = new IntersectionObserver((entries) => {
      entries.forEach(e => {
        if (e.isIntersecting) {
          e.target.style.opacity  = '1';
          e.target.style.transform = 'translateY(0)';
          io.unobserve(e.target);
        }
      });
    }, { threshold: 0.1 });
    items.forEach(el => {
      el.style.opacity   = '0';
      el.style.transform = 'translateY(20px)';
      el.style.transition = 'opacity 0.5s ease, transform 0.5s ease';
      io.observe(el);
    });
  }
})();
