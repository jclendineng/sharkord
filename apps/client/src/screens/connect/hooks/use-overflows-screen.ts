import { useEffect, useState } from 'react';

// whether the content is taller than the screen with safari's toolbar showing (the small
// viewport). measured against a hidden 100svh probe, since innerHeight changes as the toolbar
// shrinks and grows and would flip the answer mid scroll
export const useOverflowsScreen = () => {
  const [content, setContent] = useState<HTMLDivElement | null>(null);
  const [overflows, setOverflows] = useState(false);

  useEffect(() => {
    if (!content) return;

    const probe = document.createElement('div');

    probe.style.cssText =
      'position:fixed;top:0;height:100svh;visibility:hidden;pointer-events:none';
    document.body.appendChild(probe);

    const observer = new ResizeObserver(() => {
      setOverflows(content.offsetHeight > probe.offsetHeight);
    });

    observer.observe(content);
    observer.observe(probe);

    return () => {
      observer.disconnect();
      probe.remove();
    };
  }, [content]);

  return { contentRef: setContent, overflows };
};
