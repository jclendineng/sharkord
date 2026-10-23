import { memo } from 'react';

type TTypingDotsProps = {
  className?: string;
};

const TypingDots = memo(({ className = '' }: TTypingDotsProps) => {
  return (
    <div className={`flex items-center gap-[3px] h-2.5 ${className}`}>
      <div className="typing-dot size-[5px] rounded-full bg-foreground" />
      <div className="typing-dot size-[5px] rounded-full bg-foreground [animation-delay:0.17s]" />
      <div className="typing-dot size-[5px] rounded-full bg-foreground [animation-delay:0.34s]" />
    </div>
  );
});

TypingDots.displayName = 'TypingDots';

export { TypingDots };
