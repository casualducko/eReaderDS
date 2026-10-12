-- A string as one word for the shell: in single quotes, which expand nothing
-- (a folder named with $, a quote or a backtick stays just a name).
return function(s)
    return "'" .. (tostring(s):gsub("'", "'\\''")) .. "'"
end
