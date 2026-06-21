export function tooltip(node: HTMLElement, text: string | undefined | null) {
  let tooltipEl: HTMLDivElement | null = null;
  let showTimer: any = null;

  function show() {
    if (showTimer) clearTimeout(showTimer);
    if (!text) return;
    
    // Remove previous if exists
    if (tooltipEl) {
      tooltipEl.remove();
    }

    // Create element
    tooltipEl = document.createElement("div");
    tooltipEl.className = "custom-floating-tooltip";
    tooltipEl.textContent = text;
    
    document.body.appendChild(tooltipEl);
    
    // Position calculation
    const rect = node.getBoundingClientRect();
    const tooltipRect = tooltipEl.getBoundingClientRect();
    
    // Default position: top centered
    let top = rect.top - tooltipRect.height - 8;
    let left = rect.left + (rect.width - tooltipRect.width) / 2;
    
    // If it's too close to the top of the window, place it below the element
    if (top < 8) {
      top = rect.bottom + 8;
    }
    
    // Constrain left/right bounds of viewport
    const viewportWidth = window.innerWidth;
    if (left < 8) {
      left = 8;
    } else if (left + tooltipRect.width > viewportWidth - 8) {
      left = viewportWidth - tooltipRect.width - 8;
    }
    
    tooltipEl.style.top = `${top + window.scrollY}px`;
    tooltipEl.style.left = `${left + window.scrollX}px`;
    
    // Trigger transition
    requestAnimationFrame(() => {
      if (tooltipEl) {
        tooltipEl.classList.add("visible");
      }
    });
  }

  function hide() {
    if (showTimer) clearTimeout(showTimer);
    if (tooltipEl) {
      const el = tooltipEl;
      el.classList.remove("visible");
      // Wait for transition to finish before removing
      setTimeout(() => {
        if (el.parentNode) {
          el.remove();
        }
      }, 120);
      tooltipEl = null;
    }
  }

  // Use mouseenter/mouseleave/focus/blur
  node.addEventListener("mouseenter", show);
  node.addEventListener("mouseleave", hide);
  node.addEventListener("focus", show);
  node.addEventListener("blur", hide);
  node.addEventListener("click", hide);

  return {
    update(newText: string | undefined | null) {
      text = newText;
      if (tooltipEl && text) {
        tooltipEl.textContent = text;
      }
    },
    destroy() {
      if (showTimer) clearTimeout(showTimer);
      if (tooltipEl) {
        tooltipEl.remove();
      }
      node.removeEventListener("mouseenter", show);
      node.removeEventListener("mouseleave", hide);
      node.removeEventListener("focus", show);
      node.removeEventListener("blur", hide);
      node.removeEventListener("click", hide);
    }
  };
}
