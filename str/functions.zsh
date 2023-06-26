push_vast () {
	if [ -z "$1" ]
	then
		echo "Please provide a vast hash"
		return 1
	fi
	aws s3 cp "s3://enhancements-dev/enhancements-data/production/vast/$1.json" "s3://enhancements-dev/enhancements-data/development/vast/$1.json"
}

ecs_scale () {
    if [ -z "$1" ]
    then
        echo "Please provide a service name"
        return 1
    fi
    if [ -z "$2" ]
    then
        echo "Please provide a desired count"
        return 1
    fi
    aws ecs update-service --cluster enhancements-production --service $1 --desired-count $2 | jq
}