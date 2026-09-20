# Dynamic pattern completion for Fabric AI.
# Patterns are read from Fabric's local index, so updates appear automatically.
function __fabric_complete_patterns
    env LC_ALL=en_US.UTF-8 fabric-ai --listpatterns --shell-complete-list 2>/dev/null
end

for cmd in fabric fabric-ai
    complete -c $cmd -s p -l pattern -x \
        -d 'Choose a Fabric pattern' \
        -a '(__fabric_complete_patterns)'
end
