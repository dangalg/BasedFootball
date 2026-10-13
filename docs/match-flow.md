# Goals and returning to play

Goals start a short celebration and disappointed reactions. A scoring player
keeps movement control; moving interrupts their celebration. Afterward, AI
players walk back to their kickoff positions using normal physical locomotion.
A receiving teammate retrieves the ball, carries it back and places it at the
centre. The controlled player walks back manually, with direction and distance
guidance. Players are not teleported by a goal restart.

The ball remains a physical body during retrieval and placement. The pickup
uses a bounded spring force and does not exempt the ball from opposing players.
The match clock stops during the goal sequence. Initial setup and an explicit
rematch still place the teams in their starting formation.
