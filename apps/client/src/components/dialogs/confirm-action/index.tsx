import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
  AutoFocus,
  buttonVariants
} from '@sharkord/ui';
import { memo } from 'react';
import { useTranslation } from 'react-i18next';
import type { TDialogBaseProps } from '../types';

type TConfirmActionDialogProps = TDialogBaseProps & {
  onCancel?: () => void;
  onConfirm?: () => void;
  title?: string;
  message?: string;
  confirmLabel?: string;
  cancelLabel?: string;
  variant?: 'danger' | 'info';
};

const ConfirmActionDialog = memo(
  ({
    isOpen,
    onCancel,
    onConfirm,
    title,
    message,
    confirmLabel,
    cancelLabel,
    variant
  }: TConfirmActionDialogProps) => {
    const { t } = useTranslation('dialogs');
    // a deleting or blocking confirm is red, as the danger it asks about
    const confirmClassName =
      variant === 'danger'
        ? buttonVariants({ variant: 'destructive' })
        : undefined;

    return (
      <AlertDialog open={isOpen}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>
              {title ?? t('confirmActionTitle')}
            </AlertDialogTitle>
            <AlertDialogDescription>
              {message ?? t('confirmActionMsg')}
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter className="gap-2">
            <AlertDialogCancel onClick={onCancel}>
              {cancelLabel ?? t('cancel')}
            </AlertDialogCancel>
            <AutoFocus>
              <AlertDialogAction
                onClick={onConfirm}
                className={confirmClassName}
              >
                {confirmLabel ?? t('confirm')}
              </AlertDialogAction>
            </AutoFocus>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    );
  }
);

export { ConfirmActionDialog };
