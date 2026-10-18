CREATE TABLE `invite_uses` (
	`id` integer PRIMARY KEY AUTOINCREMENT NOT NULL,
	`invite_id` integer NOT NULL,
	`user_id` integer NOT NULL,
	`created_at` integer NOT NULL,
	FOREIGN KEY (`invite_id`) REFERENCES `invites`(`id`) ON UPDATE no action ON DELETE cascade,
	FOREIGN KEY (`user_id`) REFERENCES `users`(`id`) ON UPDATE no action ON DELETE cascade
);
--> statement-breakpoint
CREATE INDEX `invite_uses_invite_created_idx` ON `invite_uses` (`invite_id`,`created_at`);--> statement-breakpoint
CREATE UNIQUE INDEX `invite_uses_user_idx` ON `invite_uses` (`user_id`);--> statement-breakpoint
ALTER TABLE `invites` ADD `deleted_at` integer;