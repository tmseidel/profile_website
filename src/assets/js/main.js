// Highlight the active navigation link
(function () {
  const currentPath = window.location.pathname;
  document.querySelectorAll("nav a").forEach((link) => {
    const href = link.getAttribute("href");
    if (
      href === currentPath ||
      (href !== "/" && currentPath.startsWith(href))
    ) {
      link.classList.add("active");
    }
  });
})();
