# Create the data frame.
emp.data <- data.frame(
  state = c (1:5), 
  emp_name = c("Rick","Dan","Michelle","Ryan","Gary"),
  salary = c(623.3,515.2,611.0,729.0,843.25), 
  
  start_date = as.Date(c("2012-01-01", "2013-09-23", "2014-11-15", "2014-05-11",
                         "2015-03-27")),
  stringsAsFactors = FALSE
)
# Print the data frame.			
print(emp.data)

extra.data <-data.frame(
  age = c(20,40,45,50,60), 

  stringsAsFactors = FALSE
)
print(extra.data)

merged <= cbind(emp.data, extra.data)
x <- c("name", "age", "gender")

response_df <- data.frame(ncol=length(x), nrow=0)
colnames(response_df) <- x
