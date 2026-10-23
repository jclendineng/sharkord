import type { TJoinedPublicUser, TJoinedRole } from '@sharkord/shared';
import { Extension, InputRule } from '@tiptap/core';
import { PluginKey } from '@tiptap/pm/state';
import Suggestion from '@tiptap/suggestion';
import {
  getMentionItemName,
  MENTION_STORAGE_KEY,
  MentionSuggestion,
  type TMentionItem,
  type TMentionStorage
} from './suggestion';

export const MentionPluginKey = new PluginKey('mention');

// the node picking an item inserts, a user mention or a role mention
const toMentionNode = (item: TMentionItem) => {
  const label = getMentionItemName(item);

  if (item.type === 'user') {
    return { type: 'mention', attrs: { userId: item.user.id, label } };
  }

  return { type: 'roleMention', attrs: { roleId: item.role.id, label } };
};

type TMentionOptions = {
  users: TJoinedPublicUser[];
  roles: TJoinedRole[];
  suggestion: typeof MentionSuggestion;
};

export const Mention = Extension.create<TMentionOptions>({
  name: MENTION_STORAGE_KEY,
  addOptions() {
    return {
      users: [],
      roles: [],
      suggestion: MentionSuggestion
    };
  },
  addStorage() {
    return {
      users: this.options.users,
      roles: this.options.roles
    };
  },
  addProseMirrorPlugins() {
    return [
      Suggestion<TMentionItem, TMentionItem>({
        editor: this.editor,
        pluginKey: MentionPluginKey,
        char: '@',
        startOfLine: false,
        allowSpaces: this.options.suggestion.allowSpaces,
        items: this.options.suggestion.items,
        render: this.options.suggestion.render,
        command: ({ editor, range, props }) => {
          editor
            .chain()
            .focus()
            .deleteRange(range)
            .insertContent([toMentionNode(props), { type: 'text', text: ' ' }])
            .run();
        }
      })
    ];
  },
  addInputRules() {
    const storage = this.storage as TMentionStorage;

    return [
      // an @name typed out in full and followed by a space becomes the mention, as if it
      // was picked. anything that is not exactly a member's or role's name stays text
      new InputRule({
        find: /(?:^|\s)@([^\s@#]+)\s$/,
        handler: ({ range, match, commands }) => {
          const typed = match[1].toLowerCase();
          const items: TMentionItem[] = [
            ...(storage.users ?? []).map((user) => ({
              type: 'user' as const,
              user
            })),
            ...(storage.roles ?? []).map((role) => ({
              type: 'role' as const,
              role
            }))
          ];
          const item = items.find(
            (candidate) => getMentionItemName(candidate).toLowerCase() === typed
          );

          if (!item) return null;

          // the range ends at the cursor, the @ sits just before the name
          const from = range.to - match[1].length - 1;

          commands.insertContentAt({ from, to: range.to }, [
            toMentionNode(item),
            { type: 'text', text: ' ' }
          ]);
        }
      })
    ];
  }
});
