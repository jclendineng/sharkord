CREATE TABLE `poll_answers` (
	`id` integer PRIMARY KEY AUTOINCREMENT NOT NULL,
	`message_id` integer NOT NULL,
	`position` integer NOT NULL,
	`text` text NOT NULL,
	`emoji` text,
	FOREIGN KEY (`message_id`) REFERENCES `polls`(`message_id`) ON UPDATE no action ON DELETE cascade
);
--> statement-breakpoint
CREATE INDEX `poll_answers_message_position_idx` ON `poll_answers` (`message_id`,`position`);--> statement-breakpoint
CREATE TABLE `poll_votes` (
	`answer_id` integer NOT NULL,
	`message_id` integer NOT NULL,
	`user_id` integer NOT NULL,
	`created_at` integer NOT NULL,
	PRIMARY KEY(`answer_id`, `user_id`),
	FOREIGN KEY (`answer_id`) REFERENCES `poll_answers`(`id`) ON UPDATE no action ON DELETE cascade,
	FOREIGN KEY (`message_id`) REFERENCES `polls`(`message_id`) ON UPDATE no action ON DELETE cascade,
	FOREIGN KEY (`user_id`) REFERENCES `users`(`id`) ON UPDATE no action ON DELETE cascade
);
--> statement-breakpoint
CREATE INDEX `poll_votes_message_user_idx` ON `poll_votes` (`message_id`,`user_id`);--> statement-breakpoint
CREATE INDEX `poll_votes_user_idx` ON `poll_votes` (`user_id`);--> statement-breakpoint
CREATE TABLE `polls` (
	`message_id` integer PRIMARY KEY NOT NULL,
	`question` text NOT NULL,
	`allow_multiple` integer NOT NULL,
	`expires_at` integer NOT NULL,
	`ended_at` integer,
	`created_at` integer NOT NULL,
	FOREIGN KEY (`message_id`) REFERENCES `messages`(`id`) ON UPDATE no action ON DELETE cascade
);
