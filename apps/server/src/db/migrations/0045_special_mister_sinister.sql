CREATE TABLE `stickers` (
	`id` integer PRIMARY KEY AUTOINCREMENT NOT NULL,
	`name` text NOT NULL,
	`description` text,
	`file_id` integer NOT NULL,
	`user_id` integer NOT NULL,
	`created_at` integer NOT NULL,
	`updated_at` integer,
	FOREIGN KEY (`file_id`) REFERENCES `files`(`id`) ON UPDATE no action ON DELETE cascade,
	FOREIGN KEY (`user_id`) REFERENCES `users`(`id`) ON UPDATE no action ON DELETE cascade
);
--> statement-breakpoint
CREATE INDEX `stickers_user_idx` ON `stickers` (`user_id`);--> statement-breakpoint
CREATE INDEX `stickers_file_idx` ON `stickers` (`file_id`);--> statement-breakpoint
ALTER TABLE `messages` ADD `sticker_id` integer REFERENCES stickers(id) ON DELETE set null;--> statement-breakpoint
CREATE INDEX `messages_sticker_idx` ON `messages` (`sticker_id`);