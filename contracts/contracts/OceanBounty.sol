pragma solidity ^0.5.0;


contract OceanBounty  {
    
        /**************  constants ********************/
    int constant public WhitelistThreshold = 5;  //whtelist threshold
    int constant public BlacklistThreshold = -5; // blacklist threshold
    int constant public punishmentMultiplier = 5; // punishment multiplier
    int public noOfTracks; // number of tracks in track registry
    
       /**************  enums ********************/
    
    enum state { sandbox, whitelist, blacklist} // list of track state options
    enum genre {jazz, blues, rocknroll, country} //list of all available genres
    
           /**************  enums ********************/
    
    event voteSuccessful (address userId, int8 trackgenre, int voteValue, uint noOfVotesToday); //event to return a successful vote transaction
    event trackCreationSuccessful(uint trackhash, address userId, int8 trackgenre, uint voteValue);  //event to return a successful track creation transaction
    
        /************* structs ***************/
       //details of each track and its history
    struct trackInfo  {
        uint hash ;       //this is a hash of all metadata (stored offchain in mongodb for that track)(also acts as track id)  
        int8 trackGenre;  //the track genre
        int trackRating;  //sum total of positive and negative votes for this track
        state trackState; //state of the track (neutral/whitelist/blacklist)
        address [] vouches; //an array of all user ids that vouched for the track
        address [] rejects; //an array of all user ids that rejected the track
        mapping(address => bool) userDidVote;
    }
    
   //details of each user and their history  
    struct userInfo{
        address userId;  //the users ID(address)
        int vouchCredits; // no vouches after the user's vouch aside penalties
        int rejectCredits; // no rejects after the user's rejct aside penalties
        uint noOfVotesInDay; // number of votes, user has made within a 24 hour period
    }

   //details of each genre 
    struct genreInfo{
        int genreScore; //number of total votes for genre
        int averageScore; // genre score divided by the total number of votes
    }

    /*************mappings**********/
    mapping (int8 => genreInfo) public genreRegistry; //mapping of all genre types and their scores
    mapping (uint => trackInfo) public trackRegistry; //mapping storage of all tracks
    mapping (address => userInfo) public userRegistry; //mapping storage of all users
    mapping (uint => trackInfo) public playlist;   // playlist mapping track hash to track
    mapping (address => uint) public timeOfVoteExpiry;//mapping to keep track if user ids in relation to their expiry time


    // constructor(){
    // 	//possibly create all available genres and stored them in genre registry
    // }
    
    /****** functions *********/
    //temporry function to create new tracks
    function proposeTrack(uint trackHash, int8 trackGenre)public{ 
        
        require(trackHash != 0, 'please check track hash is not 0 and retry'); //ensure trackhash input is not 0
        require(trackRegistry[trackHash].hash == 0, 'this track hash has been used already please try again'); //check if track has been created already
        require(trackGenre <= 3, 'please entere a valid genre number between 0 and 2'); //ensure genre input is valid
        trackInfo memory track ;  //created temporary instance of a track
        track.hash = trackHash;  // assign the temporary instance of track a hash value
        track.trackGenre = trackGenre; //store track genre in track details


        userInfo memory user;  //created temporary instance of a user
        user.userId = msg.sender;  // assign the temporary of user instance a track hash value
        user.vouchCredits = 1; //automatic vouch for track creation
        userRegistry[msg.sender] = user;//store user in registry
        
        trackRegistry[trackHash] = track;//store track in registry
        updateUserIdToVote(trackHash, 1,msg.sender); //update array registry of users who have vouched for this track        
        noOfTracks++; //increment the number of tracks
        updateGenreInfo(trackGenre); //update genre information
        updateNumberOfVotesPerDay(msg.sender);  // update no of votes per day of user

        emit trackCreationSuccessful(trackHash, msg.sender,trackGenre, 1);  // emit event that track was created successfuly
    }


    // this function is used to create new users, which are neccesary to place votes
    function createNewUser()public{ 
    	userInfo memory newUser; // create temporary instance of a new user 
    	newUser.userId = msg.sender; //define userID
    	userRegistry[msg.sender] = newUser; //store user information in registry       
    }    
    
    
    //this function vouches or rejects the given track based on user vote 
    function vouchOrReject(uint trackHash, int didVouch)public {        
        address userId = msg.sender; //create a temporary address instance for userID, this is declared this way so that the user ID can always be easily changed to a different type
        trackInfo storage track = trackRegistry[trackHash];//retrieve track information from storage

        require(userRegistry[userId].userId != address(0),'user information is not in registry, please create new user'); //ensure user is registered
        require(uint8(trackRegistry[trackHash].trackState) != 2, 'selected track is blacklisted');// ensure track is not blacklisted
        require(!track.userDidVote[userId], 'you have already voted on this track'); //check if user has previously voted for this track
        require(updateNumberOfVotesPerDay(userId),'you have exceeded your number of votes for today, please try after 24hrs');//check if user has votes more than 10 times in a day
        require((didVouch == -1 || didVouch == 1 ), 'ensure that didvouch paramater is either -1 or 1'); // require didvouch param to be either equal to -1 or 1 to avoid excessive lines of code.(-1 = reject, 1= vouch). This code line can easliy be updated in future to allow more voting options
        
        updateTrackRating(trackHash,didVouch); // update the track track rating score based on vouch or reject
        updateState(trackHash,track.trackGenre);//call function to update the state of the track- sandbox, whitelist, blacklist 
        updateCredits(trackHash,didVouch,userId);//update user vouch or reject credits
        updateGenreInfo(track.trackGenre);  //update genre registry with relevant information such as genre score and average score      
        track.userDidVote[userId] = true; //record that user has voted on this track, to prevent multiple votes a track from the same user
        
        emit voteSuccessful(userId,track.trackGenre, didVouch, userRegistry[userId].noOfVotesInDay); //emit event that vote was successful
    }


    //function to updated genre registry and information
    function updateGenreInfo(int8 trackGenre)internal {
    	genreInfo storage _genre = genreRegistry[trackGenre]; // retrieve genre information from registry
    	_genre.genreScore++; //increment genre score
    	_genre.averageScore = _genre.genreScore/noOfTracks; //update average score
    	}

    
    //internal function to update the state of each track and user based on specified mechanics
    function updateState(uint trackHash, int8 trackGenre)internal {
        trackInfo storage track = trackRegistry[trackHash]; //retrieve track information from registry
        
        if(uint8(track.trackState) == uint8 (state.sandbox) && track.trackRating > WhitelistThreshold) { // check if whitelisting mechanics are met
            uint8(track.trackState) == uint8(state.whitelist); //update state to whitelist
            playlist[trackHash] = track;  // if whitelisted, save track to playlist
            applyWhitelistPenalty(trackHash); // aply whitelist penalty
        }else if(uint8(track.trackState) == uint8(state.sandbox) && track.trackRating < BlacklistThreshold) { //check if blacklisting mechanics are met
            uint8(track.trackState) == uint8(state.blacklist); //update state to blacklist
            applyBlacklistPenalty(trackHash, trackGenre); // call function to penalize vouches for blacklisted tracks
            delete trackRegistry[trackHash]; // if blacklisted, then remove from registry
            delete playlist[trackHash]; // if blacklisted, delet from playlist
            noOfTracks-- ; //reduce number of track count
        }
        return; // if non of the conditions are met, do nothing
    }


         //penalize voters who rejected tracks that are whitelisted
    function applyWhitelistPenalty(uint trackHash)internal{
        trackInfo storage track = trackRegistry[trackHash]; //retrieve track information from registry
        int _trackRating = track.trackRating; // retrieve track rating
        int penalityScore = _trackRating - WhitelistThreshold; //calculate penalty score
        address _userId; //create temporary address type of user ID
        uint length = track.rejects.length; // get the length of array containing the address of all users who voted reject on track
                
            for(uint i=0; i<length ; i++){ // loop through all voters of reject and apply penalty
                _userId = track.rejects[i];//retrieve user ids
                userRegistry[_userId].vouchCredits -= penalityScore; //apply penalty 
            }
        }    


       //penalize voters who vouched for tracks that are blacklisted
    function applyBlacklistPenalty(uint trackHash, int8 _genre)internal{
        trackInfo storage track = trackRegistry[trackHash];  //retrieve track information from registry
        int _averageScore = genreRegistry[_genre].averageScore; // retrieve genre average score
        int penalityScore = _averageScore * punishmentMultiplier;  //calculate penalty score
        address _userId;  //create temporary address type of user ID
        uint length = track.vouches.length;  // get the length of array containing the address of all users who voted vouch on track
                
            for(uint i=0; i<length ; i++){  // loop through all voters of vouch on the track and apply penalty
                _userId = track.vouches[i];//retrieve user ids
                userRegistry[_userId].rejectCredits -= penalityScore; //apply penalty 
            }
        }

      // function to update arrays within tracks that contain all user ids of all vouches and rejections
    function updateUserIdToVote(uint trackHash, int didVouch,address userId)internal{        
        trackInfo storage track = trackRegistry[trackHash]; //retrieve track information from registry
        if(didVouch == 1){
            track.vouches.push(userId); //update array of users who vouched for the track
        }
        else if(didVouch == -1){
            track.rejects.push(userId); //update array of users who rejected the track
        } 
    }    
    
    
       //this function assigns credits to users appropriately based on vote type(vouch/reject)
    function updateTrackRating(uint trackHash, int didVouch)internal{
        trackInfo storage track = trackRegistry[trackHash]; //retrieve track information from registry
        track.trackRating = track.trackRating + didVouch;//update average score        
        }        
    
    
    //this function checks if user is allowed to vote based on daily vote limits 
    function updateNumberOfVotesPerDay(address userId)internal returns (bool){

        if (timeOfVoteExpiry[userId] == 0){ //check if its the first time the user is voting
            timeOfVoteExpiry[userId] = now + 1 days;// set expiration time
            userRegistry[userId].noOfVotesInDay  = 1; // increase the number of votes the user has made in a day
            return true;            
       } else{
       		uint expirationTime = timeOfVoteExpiry[userId];
       		//userRegistry[userId].noOfVotesInDay < 11 ||
       		if (now > expirationTime ){ //check if time is expired
	            timeOfVoteExpiry[userId] = now + 1 days; //expiration time is due, so reset expiration time
	            userRegistry[userId].noOfVotesInDay +=1; // increment user votes in a day if expiration time is passed
            	return true;
	        }else{
	        if (userRegistry[userId].noOfVotesInDay < 10){ //check if user has exceeded number of allowed votes in a day
	        	userRegistry[userId].noOfVotesInDay +=1; // increment user votes in a day if less than limit
	        	return true;
	        }
	        	return false;
	    }
	      } 
    }      


    //this function updates all subsequent user credits based on vote type
    function updateCredits(uint trackHash, int didVouch, address userId)internal{       
        trackInfo storage track = trackRegistry[trackHash];  //retrieve track information from registry
        userInfo storage user = userRegistry[userId];
        address _userId;
        
        if (didVouch == -1){      // if the vote is a reject, then loop through all previous rejects and increment all address with a reject credit of +1  	
            uint length = track.rejects.length;  //get array length of previous addressed who have voted reject          
            for(uint i=0; i<length ; i++){
                _userId = track.rejects[i];//retrieve user ids
                userRegistry[_userId].rejectCredits++; //update all previous users with relevant reject credits
            }
            user.rejectCredits++; // update users reject credits
            updateUserIdToVote(trackHash, didVouch,userId); // update vouch/reject array with users vote type
        } else if(didVouch == 1 ){      // if the vote is a vouch, then loop through all previous vouches and increment all address with a vouch credit of +1   	
            uint length = track.vouches.length; //get array length of previous addressed who have vouched
                
            for(uint i=0; i<length ; i++){
                _userId = track.vouches[i];//retrieve user ids
                userRegistry[_userId].vouchCredits++; //update all previous users with relevant vouch credits
            }
            user.vouchCredits++; // update users reject credits
            updateUserIdToVote(trackHash, didVouch,userId); // update vouch/reject array with users vote type
            } 
    }    
}
    
    
    
 

