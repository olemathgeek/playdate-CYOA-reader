-- story.lua
-- Edit STORY below to write your own adventure.
--
-- STORY_TITLE = name shown on the title screen
-- STORY_START = id of the first page
--
-- Each page in STORY is keyed by a unique id and has:
--   text    = what the reader sees (keep sentences short for early readers)
--   choices = list of { label = "what to do", to = "page id" }
--   ending  = true for a last page (no choices needed)
--
-- Tip: use plain quotes (") and apostrophes ('), not curly ones.

STORY_TITLE = "Pip and the Red Ball"
STORY_START = "start"

STORY = {
    start = {
        text = "Pip is a little dog. Pip has a red ball. He likes it a lot. One day, the ball rolls away! Where did it go?",
        choices = {
            { label = "Look in the park.", to = "park" },
            { label = "Look by the pond.", to = "pond" },
        },
    },

    park = {
        text = "Pip runs to the park. The grass is big and green. Pip sees a cat on a bench. Pip sees a hole by a tree.",
        choices = {
            { label = "Ask the cat.",      to = "cat" },
            { label = "Look in the hole.", to = "hole" },
        },
    },

    cat = {
        text = "\"Hi, Cat! Did you see my red ball?\" The cat yawns. \"Yes. It went up the hill.\" \"Thank you, Cat!\"",
        choices = {
            { label = "Go up the hill.",       to = "hill" },
            { label = "Take a nap with Cat.",  to = "nap" },
        },
    },

    nap = {
        text = "Pip is sleepy too. Pip naps in the sun with the cat. When Pip wakes up, the red ball is next to him! A kind boy found it. The End.",
        ending = true,
    },

    hole = {
        text = "Pip digs in the hole. Dig, dig, dig! Pip finds a bone. It is not a ball. But it is a good bone!",
        choices = {
            { label = "Take the bone home.", to = "bone" },
            { label = "Keep looking.",       to = "hill" },
        },
    },

    bone = {
        text = "Pip takes the bone home. He naps with it in his bed. Then Mom finds the red ball under the bed! It was home all along. The End.",
        ending = true,
    },

    pond = {
        text = "Pip runs to the pond. A duck swims by. Quack! Pip sees a red thing in the water. Is it the ball?",
        choices = {
            { label = "Jump in the pond.",  to = "swim" },
            { label = "Ask the duck.",      to = "duck" },
        },
    },

    swim = {
        text = "Splash! Pip swims to the red thing. It is not the ball. It is a red hat! A frog sits on a log. The frog looks sad.",
        choices = {
            { label = "Give the hat to the frog.", to = "frog" },
            { label = "Swim back.",                to = "wet" },
        },
    },

    frog = {
        text = "Pip puts the hat on the frog. The frog is glad! The frog hops and points. \"Look! Your ball is up on the hill.\"",
        choices = {
            { label = "Go up the hill.", to = "hill" },
        },
    },

    wet = {
        text = "Pip swims back. Shake, shake, shake! Pip is wet, but he is happy. He will look for the ball when it is sunny. The End.",
        ending = true,
    },

    duck = {
        text = "\"Can you help me, Duck?\" The duck flaps up, up, up. \"Quack! I see it! It is on the hill!\"",
        choices = {
            { label = "Go up the hill.", to = "hill" },
        },
    },

    hill = {
        text = "Pip runs up the hill. It is a big hill! At the top, Pip sees the red ball. But a big goat is next to it.",
        choices = {
            { label = "Say hi to the goat.",     to = "goat" },
            { label = "Grab the ball and run!",  to = "run" },
        },
    },

    goat = {
        text = "\"Hi, Goat! Is that my ball?\" \"Yes,\" says the goat. \"I kept it safe for you.\" Pip and the goat play catch. Pip has a new friend! The End.",
        ending = true,
    },

    run = {
        text = "Pip grabs the ball and runs. Zoom! He runs down the hill, past the pond, and back home. Pip is home with his red ball. The End.",
        ending = true,
    },
}
