CREATE TABLE `friendships` (
	`user_one_id` integer NOT NULL,
	`user_two_id` integer NOT NULL,
	`requester_id` integer NOT NULL,
	`status` text NOT NULL,
	`created_at` integer NOT NULL,
	`accepted_at` integer,
	PRIMARY KEY(`user_one_id`, `user_two_id`),
	FOREIGN KEY (`user_one_id`) REFERENCES `users`(`id`) ON UPDATE no action ON DELETE cascade,
	FOREIGN KEY (`user_two_id`) REFERENCES `users`(`id`) ON UPDATE no action ON DELETE cascade,
	FOREIGN KEY (`requester_id`) REFERENCES `users`(`id`) ON UPDATE no action ON DELETE cascade
);
--> statement-breakpoint
CREATE INDEX `friendships_user_two_idx` ON `friendships` (`user_two_id`);