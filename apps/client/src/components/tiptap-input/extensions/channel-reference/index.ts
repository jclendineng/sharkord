import type { TChannel } from '@sharkord/shared';
import { Extension, InputRule } from '@tiptap/core';
import { PluginKey } from '@tiptap/pm/state';
import Suggestion from '@tiptap/suggestion';
import {
  CHANNEL_REF_STORAGE_KEY,
  ChannelReferenceSuggestion
} from './suggestion';

export const ChannelReferencePluginKey = new PluginKey('channelReference');

type TChannelReferenceOptions = {
  channels: TChannel[];
  suggestion: typeof ChannelReferenceSuggestion;
};

export const ChannelReference = Extension.create<TChannelReferenceOptions>({
  name: CHANNEL_REF_STORAGE_KEY,
  addOptions() {
    return {
      channels: [],
      suggestion: ChannelReferenceSuggestion
    };
  },
  addStorage() {
    return {
      channels: this.options.channels
    };
  },
  addProseMirrorPlugins() {
    return [
      Suggestion<TChannel, TChannel>({
        editor: this.editor,
        pluginKey: ChannelReferencePluginKey,
        char: '#',
        startOfLine: false,
        allowSpaces: this.options.suggestion.allowSpaces,
        items: this.options.suggestion.items,
        render: this.options.suggestion.render,
        command: ({ editor, range, props }) => {
          editor
            .chain()
            .focus()
            .deleteRange(range)
            .insertContent([
              {
                type: 'channelReference',
                attrs: { channelId: props.id }
              },
              { type: 'text', text: ' ' }
            ])
            .run();
        }
      })
    ];
  },
  addInputRules() {
    const storage = this.storage as { channels?: TChannel[] };

    return [
      // a #name typed out in full and followed by a space becomes the reference, as if it
      // was picked. anything that is not exactly a channel's name stays text
      new InputRule({
        find: /(?:^|\s)#([^\s@#]+)\s$/,
        handler: ({ state, range, match }) => {
          const typed = match[1].toLowerCase();
          const channel = (storage.channels ?? []).find(
            (candidate) => candidate.name.toLowerCase() === typed
          );

          if (!channel) return null;

          // the range already ends past the space just typed, so the # is the name's
          // length plus two before its end
          const from = range.to - match[1].length - 2;
          const { tr, schema } = state;

          tr.replaceWith(from, range.to, [
            schema.nodes.channelReference.create({ channelId: channel.id }),
            schema.text(' ')
          ]);
        }
      })
    ];
  }
});
