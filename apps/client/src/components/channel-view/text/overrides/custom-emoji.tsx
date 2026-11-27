import { useCustomEmojiFile } from '@/features/server/emojis/hooks';
import { useFileTokensVersion } from '@/helpers/file-tokens';
import { getFileUrl } from '@/helpers/get-file-url';
import { memo, useMemo } from 'react';

type TCustomEmojiOverrideProps = {
  name: string;
  src: string;
  alt?: string;
};

// a message keeps the signed link its emoji had when it was sent, which runs out, so the
// emoji is drawn from the server's own copy of it whenever that is still around
const CustomEmojiOverride = memo(
  ({ name, src, alt }: TCustomEmojiOverrideProps) => {
    const file = useCustomEmojiFile(name);
    const fileTokensVersion = useFileTokensVersion();

    const url = useMemo(
      () => (file ? getFileUrl(file) : src),
      // the version is what moves the link on once it runs out
      // eslint-disable-next-line react-hooks/exhaustive-deps
      [file, src, fileTokensVersion]
    );

    return <img src={url} alt={alt} draggable={false} loading="lazy" />;
  }
);

export { CustomEmojiOverride };
