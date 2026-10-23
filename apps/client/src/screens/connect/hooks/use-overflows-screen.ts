import { useEffect, useState } from 'react';

const createProbe = (height: string) => {
  const probe = document.createElement('div');

  probe.style.cssText = `position:fixed;top:0;height:${height};visibility:hidden;pointer-events:none`;
  document.body.appendChild(probe);

  return probe;
};

// whether the content is taller than the screen with safari's toolbar showing (the small
// viewport), measured against a hidden 100svh probe, and how much the toolbar takes up. only
// the content's own size changes the answer: ios 26 safari grows svh as the toolbar tucks
// away, so following the probe would flip it mid scroll. the toolbar is measured once, while
// it still shows
export const useOverflowsScreen = () => {
  const [content, setContent] = useState<HTMLDivElement | null>(null);
  const [overflows, setOverflows] = useState(false);
  const [toolbarHeight, setToolbarHeight] = useState(0);

  useEffect(() => {
    if (!content) return;

    const small = createProbe('100svh');
    const large = createProbe('100lvh');

    const toolbar = Math.max(0, large.offsetHeight - small.offsetHeight);

    large.remove();

    // the observer reports once as soon as it starts, which is when the toolbar height lands
    const observer = new ResizeObserver(() => {
      setToolbarHeight(toolbar);
      setOverflows(content.offsetHeight > small.offsetHeight);
    });

    observer.observe(content);

    return () => {
      observer.disconnect();
      small.remove();
    };
  }, [content]);

  return { contentRef: setContent, overflows, toolbarHeight };
};
