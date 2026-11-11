import { FileCard } from '@/components/channel-view/text/file-card';
import { requestConfirmation } from '@/features/dialogs/actions';
import { getFileUrl } from '@/helpers/get-file-url';
import { getTRPCClient } from '@/lib/trpc';
import type { TFile } from '@sharkord/shared';
import { getTrpcError } from '@sharkord/shared';
import { PaginatedList } from '@sharkord/ui';
import { memo, useCallback } from 'react';
import { useTranslation } from 'react-i18next';
import { toast } from 'sonner';
import { useModViewContext } from '../context';

const searchFilter = (file: TFile, term: string) =>
  file.originalName.toLowerCase().includes(term.toLowerCase()) ||
  file.extension.toLowerCase().includes(term.toLowerCase());

type TFileRowProps = {
  file: TFile;
  onRemoveClick: (fileId: number) => void;
};

// its own component so the remove handler has a file to close over: the list draws its rows
// from a function, where a hook cannot be called
const FileRow = memo(({ file, onRemoveClick }: TFileRowProps) => {
  const onRemove = useCallback(() => {
    onRemoveClick(file.id);
  }, [onRemoveClick, file.id]);

  return (
    <FileCard
      name={file.originalName}
      extension={file.extension}
      size={file.size}
      onRemove={onRemove}
      href={getFileUrl(file)}
    />
  );
});

const getFileKey = (file: TFile) => file.id;

const Files = memo(() => {
  const { t } = useTranslation('settings');
  const { files, refetch } = useModViewContext();

  const onRemoveClick = useCallback(
    async (fileId: number) => {
      const answer = await requestConfirmation({
        title: t('deleteFileTitle'),
        message: t('deleteFileMsg'),
        confirmLabel: t('deleteBtn'),
        cancelLabel: t('cancel')
      });

      if (!answer) return;

      try {
        const trpc = getTRPCClient();

        await trpc.files.delete.mutate({ fileId });
        toast.success(t('fileDeletedSuccess'));
      } catch (error) {
        toast.error(getTrpcError(error, t('failedDeleteFile')));
      } finally {
        refetch();
      }
    },
    [refetch, t]
  );

  return (
    <PaginatedList items={files} itemsPerPage={12} searchFilter={searchFilter}>
      <PaginatedList.Search
        placeholder={t('searchFilesPlaceholder')}
        className="mb-2"
      />
      <PaginatedList.Empty className="text-xs">
        {t('noFilesUploaded')}
      </PaginatedList.Empty>
      <PaginatedList.List<TFile>
        className="flex flex-col gap-2"
        getItemKey={getFileKey}
      >
        {(file) => <FileRow file={file} onRemoveClick={onRemoveClick} />}
      </PaginatedList.List>
      <PaginatedList.Pagination className="mt-2" />
    </PaginatedList>
  );
});

export { Files };
