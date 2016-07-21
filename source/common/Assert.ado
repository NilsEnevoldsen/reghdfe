REPLACE WITH _assert

// -------------------------------------------------------------
// Simple assertions
// -------------------------------------------------------------
cap pr drop Assert
pr Assert
    syntax anything(everything equalok) [, MSG(string asis) RC(integer 198)]
    if !(`anything') {
        di as error `msg'
        exit `rc'
    }
end
*THIS IS THE SAME AS _assert !!!!!!!!!!!!!!!!!!!!!!!!!!
