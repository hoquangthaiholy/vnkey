<script setup>
import { ref, nextTick } from "vue";

const props = defineProps({
  text: {
    type: String,
    required: true
  },
  isDarkMode: {
    type: Boolean,
    default: true
  }
});

const isVisible = ref(false);
const triggerRef = ref(null);
const tooltipRef = ref(null);

const tooltipStyle = ref({
  top: '0px',
  left: '0px'
});

async function showTooltip() {
  isVisible.value = true;
  await nextTick();

  if (!triggerRef.value) return;

  const rect = triggerRef.value.getBoundingClientRect();
  const viewportWidth = window.innerWidth;
  const viewportHeight = window.innerHeight;

  let top = rect.bottom + 6;
  let left = rect.left;

  // Measure tooltip size after DOM update
  const tooltipWidth = tooltipRef.value ? tooltipRef.value.offsetWidth : 260;
  const tooltipHeight = tooltipRef.value ? tooltipRef.value.offsetHeight : 40;

  // Prevent right overflow
  if (left + tooltipWidth > viewportWidth - 16) {
    left = Math.max(16, viewportWidth - tooltipWidth - 16);
  }

  // Prevent bottom overflow (flip to above if too close to bottom edge)
  if (top + tooltipHeight > viewportHeight - 16) {
    top = Math.max(16, rect.top - tooltipHeight - 6);
  }

  tooltipStyle.value = {
    top: `${top}px`,
    left: `${left}px`
  };
}

function hideTooltip() {
  isVisible.value = false;
}
</script>

<template>
  <div 
    ref="triggerRef"
    class="inline-flex items-center"
    @mouseenter="showTooltip"
    @mouseleave="hideTooltip"
    @focusin="showTooltip"
    @focusout="hideTooltip"
  >
    <!-- Trigger Button -->
    <slot>
      <button 
        type="button"
        class="w-3.5 h-3.5 rounded-full flex items-center justify-center text-[9px] font-mono font-bold transition-colors cursor-help shrink-0 opacity-60 hover:opacity-100 focus:outline-none"
        :class="isDarkMode 
          ? 'bg-slate-800 text-slate-300 hover:bg-blue-600 hover:text-white' 
          : 'bg-slate-200 text-slate-600 hover:bg-blue-600 hover:text-white'"
        aria-label="Thông tin chi tiết"
      >
        i
      </button>
    </slot>

    <!-- Teleported Floating Tooltip (Fixed position on body, ZERO scrollbar overflow) -->
    <Teleport to="body">
      <Transition name="tooltip-fade">
        <div 
          v-if="isVisible"
          ref="tooltipRef"
          :style="tooltipStyle"
          class="fixed z-[9999] px-3 py-2 rounded-lg text-[11px] font-normal leading-relaxed whitespace-normal min-w-[180px] max-w-[320px] shadow-2xl border pointer-events-none transition-opacity duration-150"
          :class="isDarkMode 
            ? 'bg-[#151c2b] text-slate-200 border-[#252f45] shadow-black/80' 
            : 'bg-slate-900 text-slate-100 border-slate-700 shadow-slate-900/40'"
        >
          {{ text }}
        </div>
      </Transition>
    </Teleport>
  </div>
</template>

<style scoped>
.tooltip-fade-enter-from,
.tooltip-fade-leave-to {
  opacity: 0;
}
.tooltip-fade-enter-active,
.tooltip-fade-leave-active {
  transition: opacity 0.15s ease;
}
</style>
