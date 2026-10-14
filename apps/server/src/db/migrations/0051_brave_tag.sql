CREATE TABLE `group_dm_members` (
	`channel_id` integer NOT NULL,
	`user_id` integer NOT NULL,
	`added_at` integer NOT NULL,
	PRIMARY KEY(`channel_id`, `user_id`),
	FOREIGN KEY (`channel_id`) REFERENCES `channels`(`id`) ON UPDATE no action ON DELETE cascade,
	FOREIGN KEY (`user_id`) REFERENCES `users`(`id`) ON UPDATE no action ON DELETE cascade
);
--> statement-breakpoint
CREATE INDEX `group_dm_members_user_idx` ON `group_dm_members` (`user_id`);--> statement-breakpoint
CREATE TABLE `group_dms` (
	`channel_id` integer PRIMARY KEY NOT NULL,
	`name` text,
	`owner_id` integer,
	`created_at` integer NOT NULL,
	FOREIGN KEY (`channel_id`) REFERENCES `channels`(`id`) ON UPDATE no action ON DELETE cascade,
	FOREIGN KEY (`owner_id`) REFERENCES `users`(`id`) ON UPDATE no action ON DELETE set null
);
