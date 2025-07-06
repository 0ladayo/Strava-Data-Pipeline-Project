from datetime import datetime, timedelta

def get_parameter_data(activity, parameter, additional_attr = None):
    """Gets a required direct or nested attribute, raising an error if it's missing or None."""
    obj = getattr(activity, parameter)

    if additional_attr:
        value = getattr(obj, additional_attr)
    else:
        value = obj
    if value is None:
        raise ValueError(f'Required {parameter} data for {activity.id} is None')
    return value


def get_activity_data(activities):
    all_activities = []
    try:
        for activity in activities:
            start_datetime = get_parameter_data(activity, 'start_date')
            elapsed_time = get_parameter_data(activity, 'elapsed_time')
            data_dict = {'id': get_parameter_data(activity, 'id'), 
            'distance': get_parameter_data(activity, 'distance'), 
            'time': elapsed_time,
            'elevation_high': get_parameter_data(activity, 'elev_high'), 
            'elevation_low': get_parameter_data(activity, 'elev_low'),
            'elevation_gain': get_parameter_data(activity, 'total_elevation_gain'), 
            'average_speed': get_parameter_data(activity, 'average_speed'), 
            'maximum_speed': get_parameter_data(activity, 'max_speed'), 
            'start_latitude': get_parameter_data(activity, 'start_latlng', 'lat'),
            'start_longitude': get_parameter_data(activity, 'start_latlng', 'lon'),
            'end_latitude': get_parameter_data(activity, 'end_latlng', 'lat'), 
            'end_longitude': get_parameter_data(activity, 'end_latlng', 'lon'), 
            'average_cadence': get_parameter_data(activity, 'average_cadence'),
            'start_datetime': start_datetime, 
            'end_datetime': start_datetime + timedelta(seconds=elapsed_time)}
            all_activities.append(data_dict)
        return all_activities
    except Exception as e:
            raise ConnectionError(f'Could not get the activity data: {e}') from e