import type { TTempFile } from '@sharkord/shared';
import { beforeEach, describe, expect, test } from 'bun:test';
import fs from 'fs/promises';
import { initTest, login, uploadFile } from '../../__tests__/helpers';
import { fileManager } from '../../helpers/file-manager';
import { verifyFileToken } from '../../helpers/files-crypto';

describe('files router', () => {
  let tempFile: TTempFile;
  let counter = 0;

  beforeEach(async () => {
    const response = await login('testowner', 'password123');
    const data: any = await response.json();

    const res = await uploadFile(
      new File(['test'], `file-${counter++}.txt`, { type: 'text/plain' }),
      data.token
    );

    tempFile = (await res.json()) as TTempFile;
  });

  test('should clean up inline replies when removing the last file deletes the message', async () => {
    const { caller } = await initTest();

    // a file only message: removing its file removes the message itself
    const fileOnlyMessageId = await caller.messages.send({
      channelId: 1,
      content: '',
      files: [tempFile.id]
    });

    const replyId = await caller.messages.send({
      channelId: 1,
      content: 'Replying to the file message',
      files: [],
      replyToMessageId: fileOnlyMessageId
    });

    const message = await caller.messages.getOne({
      messageId: fileOnlyMessageId
    });

    expect(message.files.length).toBe(1);

    await caller.files.delete({ fileId: message.files[0]!.id });

    await expect(
      caller.messages.getOne({ messageId: fileOnlyMessageId })
    ).rejects.toThrow('Message not found');

    // the same cleanup messages.delete performs, this path used to skip it
    const reply = await caller.messages.getOne({ messageId: replyId });

    expect(reply.replyToMessageId).toBeNull();
    expect(reply.replyTo).toBeNull();
  });

  test('should update the parent reply count when a thread reply loses its last file', async () => {
    const { caller } = await initTest();

    const parentId = await caller.messages.send({
      channelId: 1,
      content: 'Thread parent',
      files: []
    });

    const threadReplyId = await caller.messages.send({
      channelId: 1,
      content: '',
      files: [tempFile.id],
      parentMessageId: parentId
    });

    const reply = await caller.messages.getOne({ messageId: threadReplyId });

    await caller.files.delete({ fileId: reply.files[0]!.id });

    const parent = await caller.messages.getOne({ messageId: parentId });

    expect(parent.replyCount).toBe(0);
  });

  test('should check temporary file existence', async () => {
    expect(tempFile).toBeDefined();
    expect(tempFile.id).toBeDefined();

    const file = await fileManager.getTemporaryFile(tempFile.id);

    expect(file).toBeDefined();
    expect(file?.path).toBe(tempFile.path);
    expect(file?.originalName).toBe(tempFile.originalName);
    expect(file?.size).toBe(tempFile.size);

    const stat = await fs.stat(tempFile.path);

    expect(stat.size).toBe(tempFile.size);
  });

  test('should delete a temporary file', async () => {
    const { caller } = await initTest();

    expect(await fs.exists(tempFile.path)).toBe(true);

    await caller.files.deleteTemporary({
      fileId: tempFile.id
    });

    expect(await fs.exists(tempFile.path)).toBe(false);
  });

  test('should throw when deleting a non-existent temporary file', async () => {
    const { caller } = await initTest();

    await expect(
      caller.files.deleteTemporary({
        fileId: '<non-existent-file-id>' // non-existent file ID
      })
    ).rejects.toThrow('Temporary file not found');
  });

  test('should throw when deleting other users temporary file', async () => {
    const { caller } = await initTest(2);

    await expect(
      caller.files.deleteTemporary({
        fileId: tempFile.id
      })
    ).rejects.toThrow(
      'You do not have permission to delete this temporary file'
    );

    expect(await fs.exists(tempFile.path)).toBe(true);
  });
});

describe('files.sign', () => {
  // user 1 posts a file in a channel, its id is what gets signed
  const postFile = async (channelId: number) => {
    const { caller, mockedToken } = await initTest(1);
    const response = await uploadFile(
      new File(['signed'], 'signed.txt', { type: 'text/plain' }),
      mockedToken
    );
    const tempFile = (await response.json()) as TTempFile;

    const messageId = await caller.messages.send({
      channelId,
      content: '',
      files: [tempFile.id]
    });

    const message = await caller.messages.getOne({ messageId });

    return message.files[0]!.id;
  };

  test('should sign a file in a channel the caller can see with a working token', async () => {
    const fileId = await postFile(1);
    const { caller } = await initTest(2);
    const before = Date.now();

    const signed = await caller.files.sign({ fileIds: [fileId] });

    expect(signed).toHaveLength(1);
    expect(signed[0]!.fileId).toBe(fileId);
    expect(signed[0]!.expiresAt).toBeGreaterThanOrEqual(before + 600_000);
    expect(
      verifyFileToken(fileId, signed[0]!.accessToken, signed[0]!.expiresAt)
    ).toBe(true);
  });

  test('should leave out a file in a channel the caller cannot see', async () => {
    // user 2 is denied viewing channel 5
    const hiddenFileId = await postFile(5);
    const visibleFileId = await postFile(1);
    const { caller } = await initTest(2);

    const signed = await caller.files.sign({
      fileIds: [hiddenFileId, visibleFileId]
    });

    expect(signed.map(({ fileId }) => fileId)).toEqual([visibleFileId]);
  });

  test('should leave out ids that do not exist', async () => {
    const { caller } = await initTest(1);

    expect(await caller.files.sign({ fileIds: [999_999] })).toEqual([]);
  });

  test('should sign a sticker for anyone signed in', async () => {
    const { caller, mockedToken } = await initTest(1);
    const response = await uploadFile(
      new File(['sticker'], 'wave.png', { type: 'image/png' }),
      mockedToken
    );
    const upload = (await response.json()) as TTempFile;
    const stickerId = await caller.stickers.add({
      fileId: upload.id,
      name: 'wave',
      description: 'says hi'
    });
    const stickers = await caller.stickers.getAll();
    const sticker = stickers.find(({ id }) => id === stickerId)!;

    const { caller: lowCaller } = await initTest(2);
    const signed = await lowCaller.files.sign({ fileIds: [sticker.file.id] });

    expect(signed.map(({ fileId }) => fileId)).toEqual([sticker.file.id]);
  });

  test('should reject an empty list and more than 200 ids', async () => {
    const { caller } = await initTest(1);

    await expect(caller.files.sign({ fileIds: [] })).rejects.toThrow();
    await expect(
      caller.files.sign({
        fileIds: Array.from({ length: 201 }, (_, index) => index + 1)
      })
    ).rejects.toThrow();
  });
});
