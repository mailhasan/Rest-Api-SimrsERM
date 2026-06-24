CREATE TABLE `user_api_token` (
  `id_user` varchar(30) NOT NULL,
  `token` varchar(50) NOT NULL,
  `last_activity` datetime NOT NULL,
  PRIMARY KEY (`id_user`),
  UNIQUE KEY `token_UNIQUE` (`token`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;