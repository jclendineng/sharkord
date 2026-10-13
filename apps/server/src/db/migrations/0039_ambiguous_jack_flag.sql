CREATE TABLE `channel_notification_settings` (
	`user_id` integer NOT NULL,
	`channel_id` integer NOT NULL,
	`level` text NOT NULL,
	`updated_at` integer NOT NULL,
	PRIMARY KEY(`channel_id`, `user_id`),
	FOREIGN KEY (`user_id`) REFERENCES `users`(`id`) ON UPDATE no action ON DELETE cascade,
	FOREIGN KEY (`channel_id`) REFERENCES `channels`(`id`) ON UPDATE no action ON DELETE cascade
);
--> statement-breakpoint
CREATE INDEX `channel_notification_settings_user_idx` ON `channel_notification_settings` (`user_id`);